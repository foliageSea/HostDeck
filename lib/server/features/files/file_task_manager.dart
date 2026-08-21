import 'dart:async';
import 'dart:math';

import 'package:host_deck/server/core/ssh/ssh_repository.dart';
import 'package:host_deck/server/core/ssh/ssh_service.dart';
import 'package:host_deck/server/core/ssh/ssh_session.dart';
import 'package:host_deck/server/features/files/file_task.dart';
import 'package:host_deck/server/features/files/file_task_repository.dart';

class FileTaskManager {
  final SshService _sshService;
  final SshRepository _repository;
  final FileTaskRepository _taskRepository;
  final Map<String, StreamController<FileTask>> _controllers = {};
  final Map<String, StreamSubscription<SshExecStreamEvent>> _runningCommands =
      {};
  final Map<String, Completer<void>> _runningCompleters = {};
  final Set<String> _cancelRequested = {};
  final Map<String, Future<void>> _connectionQueues = {};
  final Random _random = Random.secure();

  FileTaskManager(this._sshService, this._repository, this._taskRepository) {
    _taskRepository.markUnfinishedAsFailed();
    _sshService.addDisconnectListener(_handleDisconnect);
  }

  FileTask create(
    String connectionId,
    FileTaskType type,
    List<Map<String, String?>> entries,
  ) {
    if (entries.isEmpty) {
      throw ArgumentError('至少需要一个文件任务项。');
    }
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
    final persisted = _taskRepository.find(task.id)!;
    _emit(persisted);
    final previous = _connectionQueues[connectionId] ?? Future<void>.value();
    _connectionQueues[connectionId] = previous
        .catchError((_) {})
        .then((_) => _run(task.id));
    return persisted;
  }

  FileTask? find(String id) => _taskRepository.find(id);

  List<FileTask> list({String? connectionId, int limit = 100}) =>
      _taskRepository.list(connectionId: connectionId, limit: limit);

  Stream<FileTask> watch(String id) {
    late final StreamController<FileTask> outputController;
    StreamSubscription<FileTask>? subscription;

    outputController = StreamController<FileTask>(
      onListen: () {
        final sourceController = _controllers.putIfAbsent(
          id,
          () => StreamController<FileTask>.broadcast(),
        );
        subscription = sourceController.stream.listen((task) {
          if (outputController.isClosed) {
            return;
          }
          outputController.add(task);
          if (_isFinished(task.status)) {
            unawaited(outputController.close());
          }
        }, onError: outputController.addError);

        final snapshot = find(id);
        if (snapshot == null || outputController.isClosed) {
          return;
        }
        outputController.add(snapshot);
        if (_isFinished(snapshot.status)) {
          unawaited(outputController.close());
        }
      },
      onCancel: () => subscription?.cancel(),
    );
    return outputController.stream;
  }

  Future<FileTask?> cancel(String id) async {
    final task = find(id);
    if (task == null || _isFinished(task.status)) return task;
    _cancelRequested.add(id);
    final completer = _runningCompleters[id];
    if (completer != null && !completer.isCompleted) {
      completer.completeError(StateError('任务已取消。'));
    }
    _runningCommands[id]?.cancel();
    if (task.status == FileTaskStatus.queued) {
      _taskRepository.updateTask(id, FileTaskStatus.cancelled);
      for (final item in task.items) {
        _taskRepository.updateItem(item.id, FileTaskStatus.cancelled);
      }
      final updated = find(id)!;
      _emit(updated);
      return updated;
    }
    return find(id);
  }

  Future<void> _run(String id) async {
    var task = find(id);
    if (task == null || task.status != FileTaskStatus.queued) return;
    _taskRepository.updateTask(id, FileTaskStatus.running);
    _emit(find(id)!);
    SshSession? session;
    var failed = false;
    try {
      session = await _sshService.createSftpSession(task.connectionId);
      task = find(id)!;
      for (final item in task.items) {
        if (_cancelRequested.contains(id)) break;
        _taskRepository.updateItem(item.id, FileTaskStatus.running);
        _emit(find(id)!);
        try {
          await _runItem(id, task.type, session, item);
          if (_cancelRequested.contains(id)) {
            _taskRepository.updateItem(item.id, FileTaskStatus.cancelled);
          } else {
            _taskRepository.updateItem(item.id, FileTaskStatus.success);
          }
        } catch (error) {
          failed = true;
          _taskRepository.updateItem(
            item.id,
            _cancelRequested.contains(id)
                ? FileTaskStatus.cancelled
                : FileTaskStatus.failed,
            errorMessage: _message(error),
          );
        }
        _emit(find(id)!);
      }
      task = find(id)!;
      if (_cancelRequested.contains(id)) {
        for (final item in task.items.where(
          (item) => item.status == FileTaskStatus.queued,
        )) {
          _taskRepository.updateItem(item.id, FileTaskStatus.cancelled);
        }
        _taskRepository.updateTask(id, FileTaskStatus.cancelled);
      } else if (failed ||
          task.items.any((item) => item.status == FileTaskStatus.failed)) {
        _taskRepository.updateTask(
          id,
          FileTaskStatus.failed,
          errorMessage: '部分文件操作失败。',
        );
      } else {
        _taskRepository.updateTask(id, FileTaskStatus.success);
      }
    } catch (error) {
      _taskRepository.updateTask(
        id,
        _cancelRequested.contains(id)
            ? FileTaskStatus.cancelled
            : FileTaskStatus.failed,
        errorMessage: _cancelRequested.contains(id) ? null : _message(error),
      );
    } finally {
      _runningCommands.remove(id);
      _cancelRequested.remove(id);
      if (session != null) await _sshService.closeSession(session.id);
      final updated = find(id);
      if (updated != null) _emit(updated);
    }
  }

  Future<void> _runItem(
    String taskId,
    FileTaskType type,
    SshSession session,
    FileTaskItem item,
  ) async {
    if (type == FileTaskType.move) {
      await _repository.rename(session, item.sourcePath, item.targetPath!);
      return;
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
    final completer = Completer<void>();
    _runningCompleters[taskId] = completer;
    final stderr = StringBuffer();
    late final StreamSubscription<SshExecStreamEvent> subscription;
    subscription = stream.listen(
      (event) {
        if (event.source == SshExecStreamSource.stderr) {
          stderr.write(event.text);
        }
        if (event.completed &&
            event.exitCode != null &&
            event.exitCode != 0 &&
            !completer.isCompleted) {
          completer.completeError(
            Exception(
              stderr.toString().trim().isEmpty
                  ? '远端命令执行失败。'
                  : stderr.toString().trim(),
            ),
          );
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      },
      onDone: () {
        if (!completer.isCompleted) completer.complete();
      },
    );
    _runningCommands[taskId] = subscription;
    try {
      await completer.future;
    } finally {
      await subscription.cancel();
      _runningCommands.remove(taskId);
      _runningCompleters.remove(taskId);
    }
  }

  Future<void> _handleDisconnect(String connectionId) async {
    for (final task in list(connectionId: connectionId, limit: 200)) {
      if (_isFinished(task.status)) continue;
      _cancelRequested.add(task.id);
      final completer = _runningCompleters[task.id];
      if (completer != null && !completer.isCompleted) {
        completer.completeError(StateError('SSH 连接已断开。'));
      }
      await _runningCommands[task.id]?.cancel();
      _taskRepository.updateTask(
        task.id,
        FileTaskStatus.failed,
        errorMessage: 'SSH 连接已断开。',
      );
      for (final item in task.items.where(
        (item) => !_isFinished(item.status),
      )) {
        _taskRepository.updateItem(
          item.id,
          FileTaskStatus.failed,
          errorMessage: 'SSH 连接已断开。',
        );
      }
      _emit(find(task.id)!);
    }
  }

  void _emit(FileTask task) {
    final controller = _controllers[task.id];
    if (controller == null || controller.isClosed) {
      return;
    }
    controller.add(task);
    if (_isFinished(task.status)) {
      scheduleMicrotask(() async {
        if (identical(_controllers[task.id], controller)) {
          _controllers.remove(task.id);
        }
        if (!controller.isClosed) {
          await controller.close();
        }
      });
    }
  }

  bool _isFinished(FileTaskStatus status) =>
      status == FileTaskStatus.success ||
      status == FileTaskStatus.failed ||
      status == FileTaskStatus.cancelled;

  String _newId() =>
      '${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}${_random.nextInt(1 << 32).toRadixString(36)}';

  String _message(Object error) {
    final value = error.toString();
    return value.length > 500 ? value.substring(0, 500) : value;
  }

  Future<void> dispose() async {
    for (final subscription in _runningCommands.values) {
      await subscription.cancel();
    }
    for (final controller in _controllers.values) {
      await controller.close();
    }
  }
}
