import 'dart:async';
import 'dart:collection';

import 'package:logging/logging.dart';

import 'package:host_deck/server/features/logs/server_log_entry.dart';

class ServerLogService {
  static const int defaultCapacity = 500;

  final int capacity;
  final ListQueue<ServerLogEntry> _entries = ListQueue<ServerLogEntry>();
  final StreamController<ServerLogEntry> _controller =
      StreamController<ServerLogEntry>.broadcast(sync: true);
  late final StreamSubscription<LogRecord> _rootSubscription;
  int _nextId = 1;
  int _subscriberCount = 0;
  bool _disposed = false;

  ServerLogService({this.capacity = defaultCapacity}) : assert(capacity > 0) {
    Logger.root.level = Level.ALL;
    _rootSubscription = Logger.root.onRecord.listen(_record);
  }

  List<ServerLogEntry> get entries => List.unmodifiable(_entries);
  int? get oldestId => _entries.isEmpty ? null : _entries.first.id;
  int? get latestId => _entries.isEmpty ? null : _entries.last.id;
  int get subscriberCount => _subscriberCount;

  bool isReplayTruncated(int? afterId) {
    final oldest = oldestId;
    final latest = latestId;
    return afterId != null &&
        ((oldest != null && afterId < oldest - 1) ||
            latest == null ||
            afterId > latest);
  }

  int? resolveCursor(int? afterId) {
    final latest = latestId;
    return afterId != null && latest != null && afterId <= latest
        ? afterId
        : null;
  }

  Stream<ServerLogEntry> subscribe({int? afterId}) {
    if (_disposed) {
      return const Stream.empty();
    }

    late final StreamController<ServerLogEntry> replayController;
    StreamSubscription<ServerLogEntry>? liveSubscription;
    replayController = StreamController<ServerLogEntry>(
      onListen: () {
        _subscriberCount++;
        liveSubscription = _controller.stream.listen(
          replayController.add,
          onError: replayController.addError,
          onDone: replayController.close,
        );
        final replay = List<ServerLogEntry>.of(_entries);
        for (final entry in replay) {
          if (afterId == null || entry.id > afterId) {
            replayController.add(entry);
          }
        }
      },
      onCancel: () async {
        _subscriberCount--;
        await liveSubscription?.cancel();
      },
    );
    return replayController.stream.where(
      (entry) => afterId == null || entry.id > afterId,
    );
  }

  void _record(LogRecord record) {
    if (_disposed) return;
    final entry = ServerLogEntry.fromRecord(_nextId++, record);
    if (_entries.length == capacity) {
      _entries.removeFirst();
    }
    _entries.addLast(entry);
    _controller.add(entry);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _rootSubscription.cancel();
    await _controller.close();
  }
}
