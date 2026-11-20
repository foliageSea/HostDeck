import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:host_deck/server/core/database/database_service.dart';
import 'package:host_deck/server/features/files/file_task.dart';
import 'package:host_deck/server/features/files/file_task_repository.dart';
import 'package:host_deck_sidecar/protocol.dart';

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

    final itemId = created!.items.single.id;
    expect(created.items.single.progress, isNull);
    repository.updateItem(itemId, FileTaskStatus.running);
    repository.updateItemProgress(
      itemId,
      const SidecarProgress(
        phase: SidecarPhase.working,
        bytesDone: 120,
        entriesDone: 2,
        entriesTotal: 3,
      ),
    );

    repository.markUnfinishedAsFailed();

    final recovered = repository.find('task-1');
    expect(recovered?.status, FileTaskStatus.failed);
    expect(recovered?.items.single.status, FileTaskStatus.failed);
    expect(recovered?.errorMessage, contains('服务已重启'));
    expect(recovered?.items.single.progress?.bytesDone, 120);
    expect(recovered?.items.single.progress?.bytesTotal, isNull);
    repository.updateItemProgress(
      itemId,
      const SidecarProgress(phase: SidecarPhase.legacy),
    );
    expect(
      repository.find('task-1')?.items.single.progress?.phase,
      SidecarPhase.working,
    );
  });

  test('upgrades v22 file task records with nullable progress', () async {
    databaseService.db.execute(
      'ALTER TABLE file_task_items DROP COLUMN progressJson',
    );
    databaseService.db.execute('UPDATE schema_version SET version = 22');
    databaseService.db.execute(
      "INSERT INTO file_tasks (id, connectionId, type, status, createdAt) VALUES ('old', 'remote', 'move', 'success', 1)",
    );
    databaseService.db.execute(
      "INSERT INTO file_task_items (taskId, itemOrder, sourcePath, status) VALUES ('old', 0, '/original', 'success')",
    );
    databaseService.close();
    databaseService = DatabaseService(dataDir: tempDirectory.path);
    await databaseService.init();
    repository = FileTaskRepository(databaseService);
    expect(repository.find('old')?.items.single.progress, isNull);
    expect(repository.find('old')?.items.single.sourcePath, '/original');
    expect(
      databaseService.db
          .select('SELECT version FROM schema_version')
          .single['version'],
      23,
    );
  });
}
