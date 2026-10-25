import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:langchain/langchain.dart';

import 'package:host_deck/server/core/database/database_service.dart';
import 'package:host_deck/server/core/ssh/shared_ssh_session_resolver.dart';
import 'package:host_deck/server/core/ssh/ssh_service.dart';
import 'package:host_deck/server/core/ssh/ssh_session.dart';
import 'package:host_deck/server/features/ai_agent/ai_agent_cron_tool_service.dart';
import 'package:host_deck/server/features/ai_agent/ai_agent_tool_service.dart';
import 'package:host_deck/server/features/crontabs/cron_task.dart';
import 'package:host_deck/server/features/crontabs/cron_task_repository.dart';
import 'package:host_deck/server/features/crontabs/cron_task_service.dart';
import 'package:host_deck/server/features/operation_logs/operation_log_repository.dart';
import 'package:host_deck/server/features/operation_logs/operation_log_service.dart';

import 'support/cron_fakes.dart';

void main() {
  late Directory dataDirectory;
  late DatabaseService database;
  late CronTaskRepository repository;
  late FakeCrontabRepository ssh;
  late _FakeDelegate delegate;
  late _RecordingOperationLogs logs;
  late _FakeSshService sshService;
  late AiAgentCronToolService service;

  Future<AiAgentToolResult> run(
    String name,
    Map<String, dynamic> arguments, {
    String connectionId = 'connection-1',
  }) {
    final normalized = service.normalizeArguments(name, arguments);
    return service.execute(
      connectionId: connectionId,
      targetKey: 'server:7',
      name: name,
      arguments: normalized,
    );
  }

  Map<String, dynamic> decode(AiAgentToolResult result) =>
      jsonDecode(result.content) as Map<String, dynamic>;

  setUp(() async {
    dataDirectory = await Directory.systemTemp.createTemp(
      'hostdeck-cron-tool-',
    );
    database = DatabaseService(dataDir: dataDirectory.path);
    await database.init();
    repository = CronTaskRepository(database);
    ssh = FakeCrontabRepository();
    delegate = _FakeDelegate();
    logs = _RecordingOperationLogs(database);
    sshService = _FakeSshService({'connection-1': 7, 'connection-2': 8});
    service = AiAgentCronToolService(
      delegate,
      sshService,
      _FakeSessionResolver(sshService),
      CronTaskService(ssh, repository),
      repository,
      logs,
    );
  });

  tearDown(() async {
    database.close();
    await dataDirectory.delete(recursive: true);
  });

  const valid = {
    'name': 'Nightly backup',
    'schedule': '0 2 * * *',
    'command': 'tar -czf /tmp/b.tgz /etc',
  };

  group('tool metadata', () {
    test('publishes cron tools after the delegate tools', () async {
      final names = (await service.resolveSpecs()).map((spec) => spec.name);

      expect(names, [
        'delegate_tool',
        'cron_list',
        'cron_create',
        'cron_update',
        'cron_delete',
      ]);
    });

    test('only listing is approval free and other tools use the delegate', () {
      expect(service.requiresApproval('cron_list'), isFalse);
      expect(service.requiresApproval('cron_create'), isTrue);
      expect(service.requiresApproval('cron_update'), isTrue);
      expect(service.requiresApproval('cron_delete'), isTrue);
      expect(service.requiresApproval('delegate_tool'), isFalse);
      expect(service.summary('delegate_tool'), 'delegate summary');
    });

    test('forwards non-cron tools to the delegate', () async {
      final result = await service.execute(
        connectionId: 'connection-1',
        targetKey: 'server:7',
        name: 'delegate_tool',
        arguments: const {},
      );

      expect(result.content, 'delegated');
    });
  });

  group('normalizeArguments', () {
    test('trims fields and defaults enabled to true on create', () {
      final result = service.normalizeArguments('cron_create', {
        'name': '  Backup ',
        'schedule': ' 0 2 * * * ',
        'command': ' echo hi ',
      });

      expect(result, {
        'name': 'Backup',
        'schedule': '0 2 * * *',
        'command': 'echo hi',
        'enabled': true,
      });
    });

    test('rejects invalid input with an explanatory ArgumentError', () {
      void expectInvalid(
        String name,
        Map<String, dynamic> arguments,
        Matcher message,
      ) {
        expect(
          () => service.normalizeArguments(name, arguments),
          throwsA(
            isA<ArgumentError>().having(
              (e) => '${e.message}',
              'message',
              message,
            ),
          ),
        );
      }

      expectInvalid('cron_create', {
        ...valid,
        'schedule': '61 * * * *',
      }, contains('Cron'));
      expectInvalid('cron_create', {
        ...valid,
        'command': 'a\nb',
      }, contains('换行'));
      expectInvalid('cron_create', {
        ...valid,
        'serverId': 99,
      }, contains('serverId'));
      expectInvalid('cron_create', {
        ...valid,
        'enabled': 'yes',
      }, contains('enabled'));
      expectInvalid('cron_create', {...valid, 'name': 5}, contains('name'));
      expectInvalid('cron_create', {
        ...valid,
        'command': 'x' * (AiAgentCronToolService.maxCommandLength + 1),
      }, contains('script'));
      expectInvalid('cron_update', {
        ...valid,
        'taskId': 1,
      }, contains('enabled'));
      expectInvalid('cron_update', {
        ...valid,
        'enabled': true,
      }, contains('taskId'));
      expectInvalid('cron_delete', {'taskId': 0}, contains('taskId'));
      expectInvalid('cron_list', {'x': 1}, contains('x'));
    });
  });

  group('execute', () {
    test('creates a task bound to the connection server', () async {
      final result = await run('cron_create', valid);

      expect(result.success, isTrue);
      final task = decode(result)['task'] as Map<String, dynamic>;
      expect(task['enabled'], isTrue);
      final stored = repository.list(7).single;
      expect(stored.id, task['id']);
      expect(stored.serverId, 7);
      expect(
        ssh.crontab,
        contains('# HOSTDECK-CRON:${stored.id}:Nightly backup'),
      );
      expect(result.details, containsPair('operation', 'create'));
      expect(result.details, containsPair('changed', true));
      expect(logs.successes, ['cron_create']);
    });

    test('lists only tasks of the connected server', () async {
      await run('cron_create', valid);
      await run('cron_create', {
        ...valid,
        'name': 'Other',
      }, connectionId: 'connection-2');

      final result = await run('cron_list', const {});

      final tasks = decode(result)['tasks'] as List;
      expect(tasks.map((t) => t['name']), ['Nightly backup']);
      expect(tasks.single['command'], valid['command']);
      expect(result.details, containsPair('changed', false));
    });

    test('updates by replacing the whole task', () async {
      final created = decode(await run('cron_create', valid))['task'] as Map;

      final result = await run('cron_update', {
        'taskId': created['id'],
        'name': 'Renamed',
        'schedule': '30 3 * * 1',
        'command': 'echo updated',
        'enabled': false,
      });

      expect(result.success, isTrue);
      final stored = repository.get(created['id'] as int)!;
      expect(stored.name, 'Renamed');
      expect(stored.enabled, isFalse);
      expect(ssh.crontab, contains('# 30 3 * * 1 '));
    });

    test('cannot update or delete a task of another server', () async {
      final other = repository.add(
        const CronTask(
          serverId: 8,
          name: 'Foreign',
          schedule: '@daily',
          command: 'true',
          enabled: true,
        ),
        connectionId: 'connection-2',
      );

      final update = await run('cron_update', {
        ...valid,
        'taskId': other.id,
        'enabled': true,
      });
      final delete = await run('cron_delete', {'taskId': other.id});

      expect(update.success, isFalse);
      expect(delete.success, isFalse);
      expect(update.content, contains('not found'));
      expect(repository.get(other.id!), isNotNull);
      expect(repository.get(other.id!)!.name, 'Foreign');
    });

    test('deletes a task and unschedules it', () async {
      final created = decode(await run('cron_create', valid))['task'] as Map;

      final result = await run('cron_delete', {'taskId': created['id']});

      expect(result.success, isTrue);
      expect(repository.list(7), isEmpty);
      expect(ssh.crontab, isNot(contains('HOSTDECK-CRON')));
    });

    test('refuses connections that are not a saved server', () async {
      sshService.serverIds['connection-3'] = null;

      final result = await run(
        'cron_create',
        valid,
        connectionId: 'connection-3',
      );

      expect(result.success, isFalse);
      expect(result.content, contains('saved server'));
      expect(ssh.writes, 0);
      expect(logs.failures, ['cron_create']);
    });

    test('reports an unreadable crontab without touching it', () async {
      ssh.crontab = '*/5 * * * * /usr/bin/own-job\n';
      ssh.readError = 'crontab: permission denied';

      final result = await run('cron_create', valid);

      expect(result.success, isFalse);
      expect(result.content, contains('permission denied'));
      expect(ssh.crontab, '*/5 * * * * /usr/bin/own-job\n');
      expect(repository.list(7), isEmpty);
    });

    test('redacts secrets from remote error messages', () async {
      ssh.writeFails = true;
      ssh.writeError = 'bad line: password=hunter2';

      final result = await run('cron_create', valid);

      expect(result.success, isFalse);
      expect(result.content, isNot(contains('hunter2')));
    });
  });
}

class _FakeDelegate implements AiAgentToolExecutor {
  @override
  Future<List<ToolSpec>> resolveSpecs({bool refresh = false}) async => const [
    ToolSpec(
      name: 'delegate_tool',
      description: 'delegate',
      inputJsonSchema: {'type': 'object'},
    ),
  ];

  @override
  bool requiresApproval(String name) => false;

  @override
  String summary(String name) => 'delegate summary';

  @override
  Map<String, dynamic> normalizeArguments(
    String name,
    Map<String, dynamic> arguments,
  ) => arguments;

  @override
  Future<AiAgentToolResult> execute({
    required String connectionId,
    required String targetKey,
    required String name,
    required Map<String, dynamic> arguments,
    AiAgentToolCancellation? cancellation,
  }) async => const AiAgentToolResult(
    success: true,
    content: 'delegated',
    summary: 'delegated',
  );
}

class _FakeSshService extends SshService {
  final Map<String, int?> serverIds;

  _FakeSshService(this.serverIds);

  @override
  int? getServerId(String connectionId) => serverIds[connectionId];
}

class _FakeSessionResolver extends SharedSshSessionResolver {
  _FakeSessionResolver(super.sshService)
    : super(
        type: SharedSshSessionType.sftp,
        purpose: SshSessionPurpose.aiAgent,
      );

  @override
  Future<SshSession> createForConnection(String connectionId) async =>
      FakeSshSession(connectionId: connectionId);
}

class _RecordingOperationLogs extends OperationLogService {
  final List<String> successes = [];
  final List<String> failures = [];

  _RecordingOperationLogs(DatabaseService database)
    : super(OperationLogRepository(database));

  @override
  void success({
    required String category,
    required String action,
    String? target,
    Map<String, dynamic>? detail,
    String? connectionId,
  }) => successes.add(action);

  @override
  void failure({
    required String category,
    required String action,
    String? target,
    Map<String, dynamic>? detail,
    String? connectionId,
    required Object error,
  }) => failures.add(action);
}
