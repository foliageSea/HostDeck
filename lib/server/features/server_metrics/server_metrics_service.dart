import 'dart:async';
import 'dart:io';

import 'package:host_deck/server/features/server_metrics/server_metrics_snapshot.dart';

typedef MetricsFileReader = Future<String?> Function(String path);

class LinuxProcessCpuSampler {
  final MetricsFileReader _readFile;
  final int _processorCount;
  int? _previousProcessTicks;
  int? _previousSystemTicks;

  LinuxProcessCpuSampler({MetricsFileReader? readFile, int? processorCount})
    : _readFile = readFile ?? _readMetricsFile,
      _processorCount = processorCount ?? Platform.numberOfProcessors;

  Future<double?> sample() async {
    final values = await Future.wait([
      _readFile('/proc/self/stat'),
      _readFile('/proc/stat'),
    ]);
    final processTicks = _parseProcessTicks(values[0]);
    final systemTicks = _parseSystemTicks(values[1]);
    if (processTicks == null || systemTicks == null) {
      return null;
    }

    final previousProcessTicks = _previousProcessTicks;
    final previousSystemTicks = _previousSystemTicks;
    _previousProcessTicks = processTicks;
    _previousSystemTicks = systemTicks;
    if (previousProcessTicks == null || previousSystemTicks == null) {
      return null;
    }

    final processDelta = processTicks - previousProcessTicks;
    final systemDelta = systemTicks - previousSystemTicks;
    if (processDelta < 0 || systemDelta <= 0) {
      return null;
    }

    return processDelta / systemDelta * _processorCount * 100;
  }

  static int? _parseProcessTicks(String? content) {
    if (content == null) return null;
    final commandEnd = content.lastIndexOf(')');
    if (commandEnd < 0 || commandEnd + 2 >= content.length) return null;
    final fields = content
        .substring(commandEnd + 2)
        .trim()
        .split(RegExp(r'\s+'));
    if (fields.length <= 12) return null;
    final userTicks = int.tryParse(fields[11]);
    final systemTicks = int.tryParse(fields[12]);
    if (userTicks == null || systemTicks == null) return null;
    return userTicks + systemTicks;
  }

  static int? _parseSystemTicks(String? content) {
    if (content == null) return null;
    final firstLine = content.split('\n').first.trim();
    final fields = firstLine.split(RegExp(r'\s+'));
    if (fields.isEmpty || fields.first != 'cpu') return null;

    var total = 0;
    for (final field in fields.skip(1)) {
      final value = int.tryParse(field);
      if (value == null) return null;
      total += value;
    }
    return total;
  }

  static Future<String?> _readMetricsFile(String path) async {
    try {
      return await File(path).readAsString();
    } on FileSystemException {
      return null;
    }
  }
}

class ServerMetricsService {
  static const _lagProbeInterval = Duration(seconds: 1);
  static const _defaultSampleInterval = Duration(seconds: 3);

  final Stopwatch _uptime = Stopwatch()..start();
  final LinuxProcessCpuSampler? _cpuSampler;
  final int Function() _currentRss;
  final int Function() _maxRss;
  final Duration _sampleInterval;
  late final StreamController<ServerMetricsSnapshot> _snapshotController;
  Timer? _lagTimer;
  Timer? _sampleTimer;
  Future<ServerMetricsSnapshot>? _sampling;
  Duration _expectedLagProbe = _lagProbeInterval;
  double _eventLoopLagMs = 0;

  ServerMetricsService({
    LinuxProcessCpuSampler? cpuSampler,
    int Function()? currentRss,
    int Function()? maxRss,
    bool? enableLinuxCpu,
    Duration sampleInterval = _defaultSampleInterval,
  }) : _cpuSampler = (enableLinuxCpu ?? Platform.isLinux)
           ? (cpuSampler ?? LinuxProcessCpuSampler())
           : null,
       _currentRss = currentRss ?? (() => ProcessInfo.currentRss),
       _maxRss = maxRss ?? (() => ProcessInfo.maxRss),
       _sampleInterval = sampleInterval {
    _snapshotController = StreamController<ServerMetricsSnapshot>.broadcast(
      onListen: _startSampling,
      onCancel: _stopSampling,
    );
    _startLagProbe();
  }

  Future<ServerMetricsSnapshot> getSnapshot() {
    final sampling = _sampling;
    if (sampling != null) return sampling;

    late final Future<ServerMetricsSnapshot> nextSampling;
    nextSampling = _collectSnapshot().whenComplete(() {
      if (identical(_sampling, nextSampling)) {
        _sampling = null;
      }
    });
    _sampling = nextSampling;
    return nextSampling;
  }

  Stream<ServerMetricsSnapshot> watchSnapshots() async* {
    yield await getSnapshot();
    yield* _snapshotController.stream;
  }

  Future<ServerMetricsSnapshot> _collectSnapshot() async {
    return ServerMetricsSnapshot(
      timestamp: DateTime.now().millisecondsSinceEpoch,
      uptimeMs: _uptime.elapsedMilliseconds,
      rssBytes: _currentRss(),
      peakRssBytes: _maxRss(),
      cpuPercent: await _cpuSampler?.sample(),
      eventLoopLagMs: _eventLoopLagMs,
    );
  }

  void _startSampling() {
    if (_sampleTimer != null) return;
    _sampleTimer = Timer.periodic(
      _sampleInterval,
      (_) => unawaited(_sampleAndPublish()),
    );
  }

  void _stopSampling() {
    if (_snapshotController.hasListener) return;
    _sampleTimer?.cancel();
    _sampleTimer = null;
  }

  Future<void> _sampleAndPublish() async {
    try {
      final snapshot = await getSnapshot();
      if (!_snapshotController.isClosed && _snapshotController.hasListener) {
        _snapshotController.add(snapshot);
      }
    } catch (error, stackTrace) {
      if (!_snapshotController.isClosed && _snapshotController.hasListener) {
        _snapshotController.addError(error, stackTrace);
      }
    }
  }

  void _startLagProbe() {
    _lagTimer = Timer.periodic(_lagProbeInterval, (_) {
      final lag = _uptime.elapsed - _expectedLagProbe;
      _eventLoopLagMs = lag.isNegative ? 0 : lag.inMicroseconds / 1000;
      _expectedLagProbe += _lagProbeInterval;
    });
  }

  Future<void> dispose() async {
    _lagTimer?.cancel();
    _lagTimer = null;
    _sampleTimer?.cancel();
    _sampleTimer = null;
    _uptime.stop();
    await _snapshotController.close();
  }
}
