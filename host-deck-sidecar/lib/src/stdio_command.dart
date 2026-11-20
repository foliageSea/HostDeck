import 'dart:async';

import 'package:host_deck_sidecar/protocol.dart';

typedef SidecarOperationRunner =
    Future<void> Function({
      required SidecarOperation operation,
      required String sourcePath,
      required String targetPath,
      required SidecarCancellation cancellation,
      required void Function(SidecarProgress) onProgress,
    });

final class _RunRequest {
  final String id;
  final SidecarOperation operation;
  final String sourcePath;
  final String targetPath;

  const _RunRequest(this.id, this.operation, this.sourcePath, this.targetPath);

  factory _RunRequest.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final operation = SidecarOperation.values
        .where((operation) => operation.name == json['operation'])
        .firstOrNull;
    if (json['type'] != 'run' ||
        id is! String ||
        !RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(id) ||
        operation == null ||
        !validSidecarPath(json['sourcePath']) ||
        !validSidecarPath(json['targetPath'])) {
      throw const FormatException('Invalid SideCar run request');
    }
    return _RunRequest(
      id,
      operation,
      json['sourcePath'] as String,
      json['targetPath'] as String,
    );
  }
}

bool validSidecarPath(Object? path) =>
    path is String && path.isNotEmpty && !path.contains(String.fromCharCode(0));

/// At most one progress update per interval within a phase. Keep transitions
/// and the latest counter update, including on failure; heartbeats are separate.
final class SidecarProgressEmitter {
  final void Function(SidecarProgress) emit;
  final Duration interval;
  final Stopwatch _elapsed = Stopwatch()..start();
  SidecarProgress? _last;
  SidecarProgress? _pending;
  Timer? _timer;

  SidecarProgressEmitter(
    this.emit, {
    this.interval = const Duration(milliseconds: 500),
  });

  void add(SidecarProgress progress) {
    if (_last?.phase != progress.phase) {
      flush();
      _send(progress);
      return;
    }
    _pending = progress;
    final delay = interval - _elapsed.elapsed;
    if (delay <= Duration.zero) {
      flush();
    } else {
      _timer ??= Timer(delay, flush);
    }
  }

  void _send(SidecarProgress progress) {
    _last = progress;
    _elapsed.reset();
    emit(progress);
  }

  void flush() {
    _timer?.cancel();
    _timer = null;
    final pending = _pending;
    _pending = null;
    if (pending != null) _send(pending);
  }
}

Future<int> runSidecarStdio({
  required Stream<List<int>> input,
  required void Function(Map<String, Object?>) writeFrame,
  required SidecarOperationRunner runOperation,
  required SidecarCancellation cancellation,
  Duration heartbeatInterval = sidecarHeartbeatInterval,
  Duration heartbeatTimeout = sidecarHeartbeatTimeout,
}) async {
  _RunRequest? request;
  final firstRequest = Completer<_RunRequest>();
  final lastPeerActivity = Stopwatch()..start();
  Object? inputError;

  void onInputError(Object error) {
    inputError ??= error;
    cancellation.cancel();
    if (!firstRequest.isCompleted) firstRequest.completeError(error);
  }

  final subscription = decodeSidecarFrames(input).listen(
    (frame) {
      if (inputError != null) return;
      try {
        if (frame['v'] is! int || frame['v'] != sidecarProtocolVersion) {
          throw const FormatException('Unsupported SideCar protocol');
        }
        if (request == null) {
          final parsed = _RunRequest.fromJson(frame);
          request = parsed;
          lastPeerActivity.reset();
          firstRequest.complete(parsed);
          return;
        }
        if (frame['id'] != request?.id ||
            (frame['type'] != 'ping' && frame['type'] != 'cancel')) {
          throw const FormatException('Invalid SideCar control frame');
        }
        lastPeerActivity.reset();
        if (frame['type'] == 'cancel') cancellation.cancel();
      } on FormatException catch (error) {
        onInputError(error);
      }
    },
    onError: onInputError,
    onDone: () {
      if (!firstRequest.isCompleted) {
        onInputError(const FormatException('SideCar run request missing'));
      } else {
        // A dead SSH connection must not leave an operation running unattended.
        cancellation.cancel();
      }
    },
  );

  try {
    final run = await firstRequest.future.timeout(heartbeatTimeout);
    void emit(String type, [Map<String, Object?> fields = const {}]) =>
        writeFrame({
          'v': sidecarProtocolVersion,
          'type': type,
          'id': run.id,
          ...fields,
        });
    void result(String status, {String? errorCode, String? message}) => emit(
      'result',
      {'status': status, 'errorCode': ?errorCode, 'message': ?message},
    );

    emit('started');
    final heartbeat = Timer.periodic(heartbeatInterval, (_) {
      if (lastPeerActivity.elapsed >= heartbeatTimeout) cancellation.cancel();
      emit('heartbeat');
    });
    final progress = SidecarProgressEmitter(
      (event) => emit('progress', {'progress': event.toJson()}),
    );
    try {
      cancellation.throwIfCancelled();
      await runOperation(
        operation: run.operation,
        sourcePath: run.sourcePath,
        targetPath: run.targetPath,
        cancellation: cancellation,
        onProgress: progress.add,
      );
      progress.flush();
      result('success');
      return 0;
    } on SidecarCancelled {
      progress.flush();
      if (inputError != null) {
        result(
          'failed',
          errorCode: 'protocol_error',
          message: 'SideCar 控制协议无效。',
        );
        return 2;
      }
      result('cancelled');
      return 130;
    } catch (error) {
      progress.flush();
      result(
        'failed',
        errorCode: error is SidecarException ? error.code : 'operation_failed',
        message: shortSidecarError(error),
      );
      return 1;
    } finally {
      heartbeat.cancel();
    }
  } on TimeoutException {
    return 2;
  } on FormatException {
    return 2;
  } finally {
    await subscription.cancel();
  }
}

String shortSidecarError(Object error) {
  final message = error.toString();
  return message.length <= 500 ? message : message.substring(0, 500);
}
