import 'dart:async';
import 'dart:math';

import 'package:host_deck/server/core/ssh/ssh_repository.dart';
import 'package:host_deck/server/core/ssh/ssh_service.dart';
import 'package:host_deck/server/core/ssh/ssh_session.dart';
import 'package:host_deck/server/features/files/file_sidecar_executor.dart';
import 'package:host_deck/server/features/files/file_task.dart';
import 'package:host_deck/server/features/files/file_task_repository.dart';
import 'package:host_deck_sidecar/protocol.dart';

class FileTaskManager {
  final SshService _sshService;
  final SshRepository _repository;
  final FileTaskRepository _taskRepository;
  final FileSidecarExecutor _sidecar;
  final Map<String, StreamController<FileTask>> _controllers = {};
  final Map<String, _ScheduledFileTask> _scheduled = {};
  final Map<String, Future<void>> _connectionQueues = {};
  final Random _random = Random.secure();
  bool _disposed = false;

  FileTaskManager(
    this._sshService,
    this._repository,
    this._taskRepository, {
    FileSidecarExecutor? sidecar,
  }) : _sidecar = sidecar ?? SshFileSidecarExecutor(_repository) {
    _taskRepository.markUnfinishedAsFailed();
    _sshService.addDisconnectListener(_handleDisconnect);
  }

  FileTask create(
    String connectionId,
    FileTaskType type,
    List<Map<String, String?>> entries,
  ) {
    if (_disposed) throw StateError('文件任务管理器已关闭。');
    if (entries.isEmpty) throw ArgumentError('至少需要一个文件任务项。');
    final task = FileTask(
      id: _newId(),
      connectionId: connectionId,
      type: type,
      status: FileTaskStatus.queued,
      errorMessage: null,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      startedAt: null,
      finishedAt: null,
      items: entries
          .map(
            (entry) => FileTaskItem(
              id: 0,
              sourcePath: entry['sourcePath']!,
              targetPath: entry['targetPath'],
              status: FileTaskStatus.queued,
              errorMessage: null,
              startedAt: null,
              finishedAt: null,
            ),
          )
          .toList(),
    );
    _taskRepository.create(task);
    final persisted = find(task.id)!;
    final scheduled = _ScheduledFileTask(connectionId);
    _scheduled[task.id] = scheduled;
    final previous = _connectionQueues[connectionId] ?? Future<void>.value();
    late final Future<void> next;
    next = previous
        .catchError((Object _) {})
        .then((_) => _run(task.id, scheduled))
        .whenComplete(() {
          _scheduled.remove(task.id);
          if (identical(_connectionQueues[connectionId], next)) {
            _connectionQueues.remove(connectionId);
          }
        });
    _connectionQueues[connectionId] = next;
    // A storage or session cleanup error must not break later tasks on the queue.
    unawaited(next.catchError((Object _) {}));
    return persisted;
  }

  FileTask? find(String id) => _taskRepository.find(id);

  List<FileTask> list({String? connectionId, int limit = 100}) =>
      _taskRepository.list(connectionId: connectionId, limit: limit);

  Stream<FileTask> watch(String id) {
    late final StreamController<FileTask> output;
    StreamSubscription<FileTask>? subscription;
    output = StreamController<FileTask>(
      onListen: () {
        final snapshot = _disposed ? null : find(id);
        if (snapshot != null) output.add(snapshot);
        if (snapshot == null || _isFinished(snapshot.status)) {
          unawaited(output.close());
          return;
        }
        final source = _controllers.putIfAbsent(
          id,
          () => StreamController<FileTask>.broadcast(
            onCancel: () => _controllers.remove(id),
          ),
        );
        subscription = source.stream.listen(
          output.add,
          onDone: () {
            unawaited(output.close());
          },
        );
      },
      onCancel: () => subscription?.cancel(),
    );
    return output.stream;
  }

  Future<FileTask?> cancel(String id) async {
    final task = find(id);
    if (task == null || _isFinished(task.status)) return task;
    _scheduled[id]?.requestCancellation();
    if (task.status == FileTaskStatus.queued) {
      for (final item in task.items) {
        _taskRepository.updateItem(item.id, FileTaskStatus.cancelled);
      }
      _taskRepository.updateTask(id, FileTaskStatus.cancelled);
      _emit(id);
    }
    // Running tasks complete only on a confirmed result (or an explicit failure).
    return find(id);
  }

  Future<void> _run(String id, _ScheduledFileTask scheduled) async {
    if (_disposed ||
        scheduled.abandoned ||
        find(id)?.status != FileTaskStatus.queued) {
      return;
    }
    _taskRepository.updateTask(id, FileTaskStatus.running);
    _emit(id);
    final connectionId = scheduled.connectionId;
    final leaseId = 'file-task:$id';
    _sshService.attachLease(connectionId, leaseId);
    SshSession? session;
    try {
      session = await _sshService.createSftpSession(
        connectionId,
        purpose: SshSessionPurpose.fileTask,
      );
      if (scheduled.abandoned || _disposed) return;
      final task = find(id)!;
      var cancelled = false;
      String? itemError;
      for (final item in task.items) {
        if (scheduled.abandoned || _disposed) return;
        if (scheduled.isCancellationRequested) {
          cancelled = true;
          _taskRepository.updateItem(item.id, FileTaskStatus.cancelled);
          continue;
        }
        _taskRepository.updateItem(item.id, FileTaskStatus.running);
        _emit(id);
        var status = FileTaskStatus.success;
        String? errorMessage;
        final progress = _ItemProgress((event) {
          if (scheduled.abandoned || _disposed) return;
          _taskRepository.updateItemProgress(item.id, event);
          _emit(id);
        });
        try {
          if (await _runItem(
            id,
            task.type,
            session,
            item,
            scheduled,
            progress.add,
          )) {
            cancelled = true;
            status = FileTaskStatus.cancelled;
          }
        } catch (error) {
          status = FileTaskStatus.failed;
          errorMessage = _message(error);
          itemError ??= errorMessage;
        } finally {
          progress.flush();
        }
        if (scheduled.abandoned || _disposed) return;
        _taskRepository.updateItem(item.id, status, errorMessage: errorMessage);
        _emit(id);
      }
      _taskRepository.updateTask(
        id,
        itemError != null
            ? FileTaskStatus.failed
            : cancelled
            ? FileTaskStatus.cancelled
            : FileTaskStatus.success,
        errorMessage: itemError,
      );
    } catch (error) {
      if (!scheduled.abandoned && !_disposed) {
        final status = scheduled.isCancellationRequested && session == null
            ? FileTaskStatus.cancelled
            : FileTaskStatus.failed;
        _finishUnfinished(
          id,
          status,
          status == FileTaskStatus.failed ? _message(error) : null,
        );
      }
    } finally {
      try {
        if (session != null) await _sshService.closeSession(session.id);
      } finally {
        _sshService.detachLease(connectionId, leaseId);
        if (!_disposed) _emit(id);
      }
    }
  }

  /// Returns true only for a confirmed cancellation (or no operation sent).
  Future<bool> _runItem(
    String taskId,
    FileTaskType type,
    SshSession session,
    FileTaskItem item,
    _ScheduledFileTask scheduled,
    void Function(SidecarProgress) onProgress,
  ) async {
    final operation = switch (type) {
      FileTaskType.copy => SidecarOperation.copy,
      FileTaskType.move => SidecarOperation.move,
      FileTaskType.extract => SidecarOperation.extract,
      FileTaskType.compress => SidecarOperation.compress,
      FileTaskType.delete => null,
    };
    if (operation != null) {
      final result = await _sidecar.run(
        session,
        id: '${taskId}_${item.id}',
        operation: operation,
        sourcePath: item.sourcePath,
        targetPath: item.targetPath!,
        onProgress: onProgress,
        cancellation: scheduled.cancellation.future,
        isCancelled: () => scheduled.isCancellationRequested,
      );
      if (result != null) return result.cancelled;
    }
    if (scheduled.isCancellationRequested) return true;
    onProgress(const SidecarProgress(phase: SidecarPhase.legacy));
    if (type == FileTaskType.move) {
      await _repository.rename(session, item.sourcePath, item.targetPath!);
      return false;
    }
    final stream = switch (type) {
      FileTaskType.copy => _repository.copyStream(
        session,
        item.sourcePath,
        item.targetPath!,
      ),
      FileTaskType.delete => _repository.deleteStream(session, item.sourcePath),
      FileTaskType.extract => _repository.extractStream(
        session,
        item.sourcePath,
        item.targetPath!,
      ),
      FileTaskType.compress => _repository.compressStream(
        session,
        item.sourcePath,
        item.targetPath!,
      ),
      FileTaskType.move => throw StateError('Unreachable'),
    };
    final complete = Completer<void>();
    final stderr = StringBuffer();
    final subscription = stream.listen(
      (event) {
        if (event.source == SshExecStreamSource.stderr && stderr.length < 500) {
          stderr.write(
            event.text.substring(
              0,
              min(500 - stderr.length, event.text.length),
            ),
          );
        }
        if (!event.completed || complete.isCompleted) return;
        if (event.exitCode == 0) {
          complete.complete();
        } else {
          final message = stderr.toString().trim();
          complete.completeError(
            StateError(message.isEmpty ? '远端命令失败或未返回退出状态。' : message),
          );
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!complete.isCompleted) complete.completeError(error, stackTrace);
      },
      onDone: () {
        if (!complete.isCompleted) {
          complete.completeError(StateError('远端命令未返回退出状态。'));
        }
      },
    );
    try {
      await Future.any<void>([
        complete.future,
        scheduled.cancellation.future.then((_) {
          if (!complete.isCompleted) {
            throw StateError('兼容模式已请求中断，远端处理结果未确认。');
          }
          return complete.future;
        }),
      ]);
      return false;
    } finally {
      await subscription.cancel();
    }
  }

  void _handleDisconnect(String connectionId) {
    for (final entry in _scheduled.entries.toList()) {
      final scheduled = entry.value;
      if (scheduled.connectionId != connectionId || scheduled.abandoned) {
        continue;
      }
      scheduled.abandon();
      _finishUnfinished(
        entry.key,
        FileTaskStatus.failed,
        'SSH 连接已断开，远端处理结果未确认。',
      );
      _emit(entry.key);
    }
  }

  void _finishUnfinished(String id, FileTaskStatus status, String? message) {
    final task = find(id);
    if (task == null || _isFinished(task.status)) return;
    for (final item in task.items.where((item) => !_isFinished(item.status))) {
      _taskRepository.updateItem(item.id, status, errorMessage: message);
    }
    _taskRepository.updateTask(id, status, errorMessage: message);
  }

  void _emit(String id) {
    final controller = _controllers[id];
    if (controller == null || controller.isClosed) return;
    final task = find(id);
    if (task == null) return;
    controller.add(task);
    if (_isFinished(task.status)) unawaited(controller.close());
  }

  bool _isFinished(FileTaskStatus status) => switch (status) {
    FileTaskStatus.success ||
    FileTaskStatus.failed ||
    FileTaskStatus.cancelled => true,
    _ => false,
  };

  String _newId() =>
      '${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}${_random.nextInt(1 << 32).toRadixString(36)}';

  String _message(Object error) {
    final value = error.toString();
    return value.length > 500 ? value.substring(0, 500) : value;
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _sshService.removeDisconnectListener(_handleDisconnect);
    for (final entry in _scheduled.entries.toList()) {
      entry.value.abandon();
      _finishUnfinished(entry.key, FileTaskStatus.failed, '服务已关闭，远端处理结果未确认。');
      _emit(entry.key);
    }
    final controllers = _controllers.values.toList();
    _controllers.clear();
    for (final controller in controllers) {
      if (!controller.isClosed) unawaited(controller.close());
    }
  }
}

final class _ScheduledFileTask {
  final String connectionId;
  final cancellation = Completer<void>();
  bool abandoned = false;

  _ScheduledFileTask(this.connectionId);

  bool get isCancellationRequested => cancellation.isCompleted;

  void requestCancellation() {
    if (!cancellation.isCompleted) cancellation.complete();
  }

  void abandon() {
    abandoned = true;
    requestCancellation();
  }
}

final class _ItemProgress {
  static const _throttle = Duration(milliseconds: 500);
  final void Function(SidecarProgress) persist;
  final _clock = Stopwatch()..start();
  SidecarPhase? _phase;
  SidecarProgress? _pending;

  _ItemProgress(this.persist);

  void add(SidecarProgress event) {
    _pending = event;
    if (_phase != event.phase || _clock.elapsed >= _throttle) flush();
  }

  void flush() {
    final event = _pending;
    if (event == null) return;
    _pending = null;
    _phase = event.phase;
    _clock.reset();
    persist(event);
  }
}
