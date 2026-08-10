import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:host_deck/server/core/database/database_service.dart';
import 'package:host_deck/server/features/crontabs/cron_task.dart';
import 'package:host_deck/server/features/crontabs/cron_task_repository.dart';

void main() {
  group('CronTaskRepository', () {
    late DatabaseService databaseService;
    late Directory dataDirectory;
    late CronTaskRepository repository;

    setUp(() async {
      dataDirectory = await Directory.systemTemp.createTemp(
        'host_deck_cron_test_',
      );
      databaseService = DatabaseService(dataDir: dataDirectory.path);
      await databaseService.init();
      repository = CronTaskRepository(databaseService);
    });

    tearDown(() async {
      databaseService.close();
      await dataDirectory.delete(recursive: true);
    });

    test('stores tasks per connection and keeps execution history', () {
      final task = repository.add(
        const CronTask(
          connectionId: 'connection-a',
          name: 'Daily backup',
          schedule: '0 2 * * *',
          command: 'echo backup',
          enabled: true,
        ),
      );
      repository.add(
        const CronTask(
          connectionId: 'connection-b',
          name: 'Other task',
          schedule: '@daily',
          command: 'echo other',
          enabled: true,
        ),
      );

      expect(repository.list('connection-a'), hasLength(1));
      expect(repository.list('connection-b'), hasLength(1));

      repository.addHistory(
        CronExecutionHistory(
          taskId: task.id!,
          connectionId: task.connectionId,
          triggerType: 'scheduled',
          startedAt: 1000,
          finishedAt: 2000,
          durationMs: 1000,
          exitCode: 0,
          status: 'success',
          stdout: 'complete',
        ),
      );
      repository.addHistory(
        CronExecutionHistory(
          taskId: task.id!,
          connectionId: task.connectionId,
          triggerType: 'scheduled',
          startedAt: 1000,
          finishedAt: 2000,
          durationMs: 1000,
          exitCode: 0,
          status: 'success',
          stdout: 'duplicate',
        ),
      );

      final history = repository.listHistory(task.id!);
      expect(history, hasLength(1));
      expect(history.single.stdout, 'complete');
    });

    test('rejects cron task input containing line breaks', () {
      expect(
        () => CronTask.fromJson({
          'connectionId': 'connection-a',
          'name': 'unsafe\nname',
          'schedule': '0 2 * * *',
          'command': 'echo safe',
        }),
        throwsArgumentError,
      );
      expect(
        () => CronTask.fromJson({
          'connectionId': 'connection-a',
          'name': 'unsafe command',
          'schedule': '0 2 * * *',
          'command': 'echo safe\nrm -rf /',
        }),
        throwsArgumentError,
      );
    });
  });
}
