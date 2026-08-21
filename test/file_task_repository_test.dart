import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:host_deck/server/core/database/database_service.dart';
import 'package:host_deck/server/features/files/file_task.dart';
import 'package:host_deck/server/features/files/file_task_repository.dart';

void main() {
  late Directory tempDirectory;
  late DatabaseService databaseService;
  late FileTaskRepository repository;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp(
      'hostdeck-file-task-',
    );
    databaseService = DatabaseService(dataDir: tempDirectory.path);
    await databaseService.init();
    repository = FileTaskRepository(databaseService);
  });

  tearDown(() async {
    databaseService.close();
    await tempDirectory.delete(recursive: true);
  });

  test('persists task items and marks unfinished tasks after restart', () {
    repository.create(
      const FileTask(
        id: 'task-1',
        connectionId: 'connection-1',
        type: FileTaskType.copy,
        status: FileTaskStatus.queued,
        errorMessage: null,
        createdAt: 1,
        startedAt: null,
        finishedAt: null,
        items: [
          FileTaskItem(
            id: 0,
            sourcePath: '/source',
            targetPath: '/target',
            status: FileTaskStatus.queued,
            errorMessage: null,
            startedAt: null,
            finishedAt: null,
          ),
        ],
      ),
    );

    final created = repository.find('task-1');
    expect(created?.items.single.sourcePath, '/source');
    expect(created?.items.single.status, FileTaskStatus.queued);

    repository.markUnfinishedAsFailed();

    final recovered = repository.find('task-1');
    expect(recovered?.status, FileTaskStatus.failed);
    expect(recovered?.items.single.status, FileTaskStatus.failed);
    expect(recovered?.errorMessage, contains('服务已重启'));
  });
}
