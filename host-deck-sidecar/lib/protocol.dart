import 'dart:convert';
import 'dart:typed_data';

const sidecarProtocolVersion = 1;
const sidecarMaxFrameBytes = 64 * 1024;
const sidecarHeartbeatInterval = Duration(seconds: 5);
const sidecarHeartbeatTimeout = Duration(seconds: 30);

const sidecarVersion = String.fromEnvironment(
  'HOSTDECK_SIDECAR_VERSION',
  defaultValue: 'dev',
);

enum SidecarOperation { copy, move, compress, extract }

enum SidecarPhase {
  deploying,
  scanning,
  working,
  committing,
  removingSource,
  legacy,
}

final class SidecarProgress {
  final SidecarPhase phase;
  final int bytesDone;
  final int? bytesTotal;
  final int entriesDone;
  final int? entriesTotal;

  const SidecarProgress({
    required this.phase,
    this.bytesDone = 0,
    this.bytesTotal,
    this.entriesDone = 0,
    this.entriesTotal,
  });

  factory SidecarProgress.fromJson(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Invalid SideCar progress');
    }
    final phase = value['phase'];
    final bytesDone = value['bytesDone'];
    final bytesTotal = value['bytesTotal'];
    final entriesDone = value['entriesDone'];
    final entriesTotal = value['entriesTotal'];
    bool validTotal(Object? total, int done) =>
        total == null || (total is int && total >= done);
    if (phase is! String ||
        bytesDone is! int ||
        bytesDone < 0 ||
        !validTotal(bytesTotal, bytesDone) ||
        entriesDone is! int ||
        entriesDone < 0 ||
        !validTotal(entriesTotal, entriesDone)) {
      throw const FormatException('Invalid SideCar progress counters');
    }
    final parsedPhase = SidecarPhase.values
        .where((value) => value.name == phase)
        .firstOrNull;
    if (parsedPhase == null) {
      throw const FormatException('Invalid SideCar progress phase');
    }
    return SidecarProgress(
      phase: parsedPhase,
      bytesDone: bytesDone,
      bytesTotal: bytesTotal as int?,
      entriesDone: entriesDone,
      entriesTotal: entriesTotal as int?,
    );
  }

  Map<String, Object?> toJson() => {
    'phase': phase.name,
    'bytesDone': bytesDone,
    'bytesTotal': bytesTotal,
    'entriesDone': entriesDone,
    'entriesTotal': entriesTotal,
  };
}

final class SidecarCancellation {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;

  void throwIfCancelled() {
    if (_cancelled) throw const SidecarCancelled();
  }
}

final class SidecarCancelled implements Exception {
  const SidecarCancelled();
}

final class SidecarException implements Exception {
  final String code;
  final String message;

  const SidecarException(this.code, this.message);

  @override
  String toString() => message;
}

/// Decode complete, LF-terminated UTF-8 JSON objects. Check wire length before
/// retaining bytes, including when a peer sends an unterminated frame.
Stream<Map<String, dynamic>> decodeSidecarFrames(
  Stream<List<int>> chunks,
) async* {
  final buffer = BytesBuilder(copy: true);
  await for (final chunk in chunks) {
    var start = 0;
    while (start < chunk.length) {
      final end = chunk.indexOf(10, start);
      final stop = end < 0 ? chunk.length : end;
      if (buffer.length + stop - start > sidecarMaxFrameBytes) {
        throw const FormatException('SideCar frame exceeds 64 KiB');
      }
      buffer.add(chunk.sublist(start, stop));
      if (end < 0) break;
      final decoded = jsonDecode(utf8.decode(buffer.takeBytes()));
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('SideCar frame must be a JSON object');
      }
      yield decoded;
      start = end + 1;
    }
  }
  if (buffer.isNotEmpty) {
    throw const FormatException('Incomplete SideCar frame');
  }
}

Uint8List encodeSidecarFrame(Map<String, Object?> frame) {
  final bytes = utf8.encode("${jsonEncode(frame)}\n");
  if (bytes.length - 1 > sidecarMaxFrameBytes) {
    throw const FormatException('SideCar frame exceeds 64 KiB');
  }
  return bytes;
}
