import 'dart:async';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:host_deck/server/core/database/database_service.dart';
import 'package:host_deck/server/core/ssh/ssh_repository.dart';
import 'package:host_deck/server/core/ssh/ssh_service.dart';
import 'package:host_deck/server/core/ssh/ssh_session.dart';
import 'package:host_deck/server/features/files/file_sidecar_executor.dart';
import 'package:host_deck_sidecar/protocol.dart';
import 'package:host_deck/server/features/files/file_task.dart';
import 'package:host_deck/server/features/files/file_task_manager.dart';
import 'package:host_deck/server/features/files/file_task_repository.dart';

void main() {
  late Directory tempDirectory;
  late DatabaseService databaseService;
  late FileTaskRepository taskRepository;
  late FileTaskManager taskManager;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp(
      'hostdeck-file-task-manager-',
    );
    databaseService = DatabaseService(dataDir: tempDirectory.path);
    await databaseService.init();
    taskRepository = FileTaskRepository(databaseService);
    taskManager = FileTaskManager(
      SshService(),
      SshRepository(),
      taskRepository,
    );
  });

  tearDown(() async {
    await taskManager.dispose();
    databaseService.close();
    await tempDirectory.delete(recursive: true);
  });

  test(
    'persists and streams real progress, including a new subscriber snapshot',
    () async {
      final ssh = _TestSshService();
      final fake = _TestSidecar();
      taskManager = FileTaskManager(
        ssh,
        SshRepository(),
        taskRepository,
        sidecar: fake,
      );
      final task = taskManager.create('connection-1', FileTaskType.copy, [
        _entry,
      ]);
      final updates = taskManager.watch(task.id).toList();
      await fake.started.future;
      final current = await taskManager.watch(task.id).first;
      expect(current.items.single.progress?.bytesDone, 42);
      expect(current.items.single.progress?.bytesTotal, 100);
      expect(ssh.leased, isTrue);
      fake.result.complete(const FileSidecarResult(cancelled: false));
      final history = await updates.timeout(const Duration(seconds: 2));
      expect(
        history.any((event) => event.items.single.progress?.bytesDone == 42),
        isTrue,
      );
      expect(history.last.status, FileTaskStatus.success);
      expect(ssh.leased, isFalse);
    },
  );

  test(
    'running cancellation waits for acknowledgement and cancels queued items',
    () async {
      final fake = _TestSidecar();
      taskManager = FileTaskManager(
        _TestSshService(),
        SshRepository(),
        taskRepository,
        sidecar: fake,
      );
      final task = taskManager.create('connection-1', FileTaskType.copy, [
        _entry,
        _entry,
      ]);
      await fake.started.future;
      expect(
        (await taskManager.cancel(task.id))?.status,
        FileTaskStatus.running,
      );
      await fake.cancelRequested.future;
      fake.result.complete(const FileSidecarResult(cancelled: true));
      final done = await taskManager
          .watch(task.id)
          .last
          .timeout(const Duration(seconds: 2));
      expect(done.status, FileTaskStatus.cancelled);
      expect(
        done.items.map((item) => item.status),
        everyElement(FileTaskStatus.cancelled),
      );
      expect(fake.calls, 1);
    },
  );

  test('confirmed commit wins over a racing cancellation', () async {
    final fake = _TestSidecar();
    taskManager = FileTaskManager(
      _TestSshService(),
      SshRepository(),
      taskRepository,
      sidecar: fake,
    );
    final task = taskManager.create('connection-1', FileTaskType.move, [
      _entry,
    ]);
    await fake.started.future;
    await taskManager.cancel(task.id);
    fake.result.complete(const FileSidecarResult(cancelled: false));
    final done = await taskManager
        .watch(task.id)
        .last
        .timeout(const Duration(seconds: 2));
    expect(done.items.single.status, FileTaskStatus.success);
    expect(done.status, FileTaskStatus.success);
  });

  test(
    'unconfirmed cancellation fails and never runs a legacy retry',
    () async {
      final fake = _TestSidecar();
      taskManager = FileTaskManager(
        _TestSshService(),
        SshRepository(),
        taskRepository,
        sidecar: fake,
      );
      final task = taskManager.create('connection-1', FileTaskType.move, [
        _entry,
      ]);
      await fake.started.future;
      await taskManager.cancel(task.id);
      fake.result.completeError(StateError('未确认远端结果'));
      final done = await taskManager
          .watch(task.id)
          .last
          .timeout(const Duration(seconds: 2));
      expect(done.status, FileTaskStatus.failed);
      expect(done.items.single.errorMessage, contains('未确认远端结果'));
    },
  );

  test(
    'disconnect fails active and pending jobs without late result overwrites',
    () async {
      final ssh = _TestSshService();
      final fake = _TestSidecar();
      taskManager = FileTaskManager(
        ssh,
        SshRepository(),
        taskRepository,
        sidecar: fake,
      );
      final first = taskManager.create('connection-1', FileTaskType.copy, [
        _entry,
      ]);
      final pending = taskManager.create('connection-1', FileTaskType.copy, [
        _entry,
      ]);
      await fake.started.future;
      await ssh.disconnected!('connection-1');
      fake.result.complete(const FileSidecarResult(cancelled: false));
      await ssh.closed.future.timeout(const Duration(seconds: 2));
      expect(taskManager.find(first.id)?.status, FileTaskStatus.failed);
      expect(
        taskManager.find(pending.id)?.items.single.status,
        FileTaskStatus.failed,
      );
      expect(fake.calls, 1);
    },
  );

  test('watch emits and closes for an already completed task', () async {
    taskRepository.create(
      const FileTask(
        id: 'task-completed',
        connectionId: 'connection-1',
        type: FileTaskType.delete,
        status: FileTaskStatus.success,
        errorMessage: null,
        createdAt: 1,
        startedAt: 1,
        finishedAt: 2,
        items: [
          FileTaskItem(
            id: 0,
            sourcePath: '/tmp/file',
            targetPath: null,
            status: FileTaskStatus.success,
            errorMessage: null,
            startedAt: 1,
            finishedAt: 2,
          ),
        ],
      ),
    );

    final events = await taskManager
        .watch('task-completed')
        .toList()
        .timeout(const Duration(seconds: 1));

    expect(events, hasLength(1));
    expect(events.single.status, FileTaskStatus.success);
  });

  test('watch observes a task that starts before subscription', () async {
    final task = taskManager.create('missing-connection', FileTaskType.delete, [
      {'sourcePath': '/tmp/file'},
    ]);

    final events = await taskManager
        .watch(task.id)
        .toList()
        .timeout(const Duration(seconds: 1));

    expect(events, isNotEmpty);
    expect(events.last.status, FileTaskStatus.failed);
  });
}

const _entry = {'sourcePath': '/source', 'targetPath': '/target'};

class _TestSidecar implements FileSidecarExecutor {
  final started = Completer<void>();
  final cancelRequested = Completer<void>();
  final result = Completer<FileSidecarResult?>();
  int calls = 0;

  @override
  Future<FileSidecarResult?> run(
    SshSession session, {
    required String id,
    required SidecarOperation operation,
    required String sourcePath,
    required String targetPath,
    required void Function(SidecarProgress) onProgress,
    required Future<void> cancellation,
    required bool Function() isCancelled,
  }) async {
    calls++;
    unawaited(cancellation.then((_) => cancelRequested.complete()));
    onProgress(
      const SidecarProgress(
        phase: SidecarPhase.working,
        bytesDone: 42,
        bytesTotal: 100,
      ),
    );
    started.complete();
    return result.future;
  }
}

class _TestSshService extends SshService {
  bool leased = false;
  FutureOr<void> Function(String)? disconnected;
  final closed = Completer<void>();

  @override
  void addDisconnectListener(
    FutureOr<void> Function(String connectionId) listener,
  ) {
    disconnected = listener;
  }

  @override
  void removeDisconnectListener(
    FutureOr<void> Function(String connectionId) listener,
  ) {
    if (disconnected == listener) disconnected = null;
  }

  @override
  Future<SshSession> createSftpSession(
    String connectionId, {
    required SshSessionPurpose purpose,
  }) async => SshSession(
    id: 'session-1',
    connectionId: connectionId,
    client: _DummyClient(),
  );

  @override
  void attachLease(String connectionId, String leaseId) => leased = true;

  @override
  void detachLease(String connectionId, String leaseId) => leased = false;

  @override
  Future<void> closeSession(String sessionId) async => closed.complete();
}

class _DummyClient implements SSHClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
