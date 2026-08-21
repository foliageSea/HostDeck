import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:host_deck/server/core/database/database_service.dart';
import 'package:host_deck/server/core/ssh/ssh_repository.dart';
import 'package:host_deck/server/core/ssh/ssh_service.dart';
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
