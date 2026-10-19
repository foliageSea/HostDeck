import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:host_deck/server/core/database/database_service.dart';
import 'package:host_deck/server/features/crontabs/cron_task.dart';
import 'package:host_deck/server/features/crontabs/cron_task_repository.dart';
import 'package:host_deck/server/features/crontabs/cron_task_service.dart';

import 'support/cron_fakes.dart';

void main() {
  group('CronTaskService', () {
    late DatabaseService databaseService;
    late Directory dataDirectory;
    late CronTaskRepository repository;
    late FakeCrontabRepository ssh;
    late CronTaskService service;
    final session = FakeSshSession();

    CronTask task(String name, {String schedule = '0 2 * * *'}) => CronTask(
      serverId: 1,
      name: name,
      schedule: schedule,
      command: 'echo $name',
      enabled: true,
    );

    setUp(() async {
      dataDirectory = await Directory.systemTemp.createTemp(
        'host_deck_cron_service_test_',
      );
      databaseService = DatabaseService(dataDir: dataDirectory.path);
      await databaseService.init();
      repository = CronTaskRepository(databaseService);
      ssh = FakeCrontabRepository();
      service = CronTaskService(ssh, repository);
    });

    tearDown(() async {
      databaseService.close();
      await dataDirectory.delete(recursive: true);
    });

    test(
      'treats a missing crontab as empty and writes managed entries',
      () async {
        final created = await service.create(session, task('backup'));

        expect(ssh.crontab, contains('# HOSTDECK-CRON:${created.id}:backup'));
        expect(ssh.crontab, contains('0 2 * * * \$HOME/.hostdeck/cron/task-'));
      },
    );

    test('never runs management commands through a login shell', () async {
      // A broken ~/.profile must not be able to break crontab management.
      final created = await service.create(session, task('backup'));
      await service.delete(session, created.id!, 1);

      expect(ssh.loginFlags, isNotEmpty);
      expect(ssh.loginFlags, everyElement(isFalse));
    });

    test('preserves unmanaged crontab entries', () async {
      ssh.crontab = '# mine\n*/5 * * * * /usr/bin/own-job\n';

      await service.create(session, task('backup'));

      expect(ssh.crontab, contains('*/5 * * * * /usr/bin/own-job'));
      expect(ssh.crontab, contains('# mine'));
    });

    test('aborts without overwriting when crontab cannot be read', () async {
      ssh.crontab = '*/5 * * * * /usr/bin/own-job\n';
      ssh.readError = 'crontab: error while loading shared libraries';

      await expectLater(
        service.create(session, task('backup')),
        throwsA(isA<StateError>()),
      );

      expect(ssh.crontab, '*/5 * * * * /usr/bin/own-job\n');
      expect(ssh.writes, 0);
      expect(repository.list(1), isEmpty);
    });

    test('rolls back the stored task when the crontab write fails', () async {
      ssh.writeFails = true;

      await expectLater(
        service.create(session, task('backup')),
        throwsA(isA<StateError>()),
      );

      expect(repository.list(1), isEmpty);
    });

    test('serializes concurrent changes for the same server', () async {
      await Future.wait([
        service.create(session, task('first')),
        service.create(session, task('second')),
        service.create(session, task('third')),
      ]);

      expect(
        RegExp('# HOSTDECK-CRON:').allMatches(ssh.crontab).length,
        3,
        reason: 'no concurrent read-modify-write may drop an entry',
      );
      expect(repository.list(1), hasLength(3));
    });

    test('a rolled-back change never leaks into a concurrent change', () async {
      ssh.failNextWrite = true;

      final broken = service.create(session, task('broken'));
      final healthy = service.create(session, task('healthy'));

      await expectLater(broken, throwsA(isA<StateError>()));
      await healthy;

      expect(ssh.crontab, contains(':healthy'));
      expect(
        ssh.crontab,
        isNot(contains(':broken')),
        reason: 'a rolled-back task must not be scheduled by another request',
      );
      expect(repository.list(1).map((t) => t.name), ['healthy']);
    });

    test('a failed change does not block later changes', () async {
      ssh.writeFails = true;
      await expectLater(
        service.create(session, task('broken')),
        throwsA(isA<StateError>()),
      );
      ssh.writeFails = false;

      await service.create(session, task('ok'));

      expect(ssh.crontab, contains(':ok'));
    });

    test('delete removes the managed entry and keeps the rest', () async {
      ssh.crontab = '*/5 * * * * /usr/bin/own-job\n';
      final created = await service.create(session, task('backup'));

      expect(await service.delete(session, created.id!, 1), isTrue);

      expect(ssh.crontab, isNot(contains('HOSTDECK-CRON')));
      expect(ssh.crontab, contains('/usr/bin/own-job'));
    });
  });

  group('generated task script', () {
    late Directory home;
    late DatabaseService databaseService;
    late Directory dataDirectory;
    late FakeCrontabRepository ssh;
    late CronTaskService service;

    setUp(() async {
      home = await Directory.systemTemp.createTemp('host_deck_cron_home_');
      dataDirectory = await Directory.systemTemp.createTemp(
        'host_deck_cron_db_',
      );
      databaseService = DatabaseService(dataDir: dataDirectory.path);
      await databaseService.init();
      ssh = FakeCrontabRepository();
      service = CronTaskService(ssh, CronTaskRepository(databaseService));
    });

    tearDown(() async {
      databaseService.close();
      await dataDirectory.delete(recursive: true);
      await home.delete(recursive: true);
    });

    /// Creates a task, then really runs its generated script under [profile].
    Future<String> runScript(String command, {required String profile}) async {
      File('${home.path}/.profile').writeAsStringSync(profile);
      final created = await service.create(
        FakeSshSession(),
        CronTask(
          serverId: 1,
          name: 'script',
          schedule: '@daily',
          command: command,
          enabled: true,
        ),
      );
      final script = ssh.files.entries
          .singleWhere((entry) => entry.key.endsWith('task-${created.id}.sh'))
          .value;
      final scriptFile = File('${home.path}/task.sh')
        ..writeAsStringSync(script);
      await Process.run(
        'sh',
        [scriptFile.path],
        environment: {'HOME': home.path, 'PATH': Platform.environment['PATH']!},
        includeParentEnvironment: false,
      );
      return File(
        '${home.path}/.hostdeck/cron/logs/task-${created.id}.log',
      ).readAsStringSync();
    }

    test('uses the login shell environment when the profile works', () async {
      final log = await runScript(
        r'echo "marker=$HOSTDECK_FROM_PROFILE"',
        profile: 'export HOSTDECK_FROM_PROFILE=yes\n',
      );

      expect(log, contains('OUT\tmarker=yes'));
      expect(log, contains('END'));
    }, skip: Platform.isWindows);

    test('falls back to a plain shell when the profile is broken', () async {
      // A profile that aborts every login shell (e.g. a bash-only file
      // sourced from sh) must not make the scheduled command fail.
      final log = await runScript('echo ran-anyway', profile: 'exit 3\n');

      expect(log, contains('OUT\tran-anyway'));
      expect(RegExp(r'END\t\d+\t0').hasMatch(log), isTrue, reason: log);
    }, skip: Platform.isWindows);
  });

  group('CronTask schedule validation', () {
    Map<String, dynamic> json(String schedule) => {
      'serverId': 1,
      'name': 'task',
      'schedule': schedule,
      'command': 'true',
    };

    test('accepts valid expressions', () {
      for (final schedule in [
        '0 2 * * *',
        '*/15 * * * *',
        '0 9-17 * * mon-fri',
        '30 3 1,15 jan,jul *',
        '0 0 * * 7',
        '5-10/2 * * * *',
        '@daily',
        '@reboot',
      ]) {
        expect(() => CronTask.fromJson(json(schedule)), returnsNormally);
      }
    });

    test('rejects out-of-range or malformed expressions', () {
      for (final schedule in [
        'a b c d e',
        '60 * * * *',
        '* 24 * * *',
        '* * 0 * *',
        '* * 32 * *',
        '* * * 13 *',
        '* * * * 8',
        '*/0 * * * *',
        '5-1 * * * *',
        '* * * * * *',
        '@sometimes',
        '1,,2 * * * *',
      ]) {
        expect(
          () => CronTask.fromJson(json(schedule)),
          throwsArgumentError,
          reason: schedule,
        );
      }
    });
  });
}
