import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:langchain/langchain.dart';

import 'package:host_deck/server/core/database/database_service.dart';
import 'package:host_deck/server/features/ai_agent/ai_agent_operation_log_tool_service.dart';
import 'package:host_deck/server/features/ai_agent/ai_agent_tool_service.dart';
import 'package:host_deck/server/features/operation_logs/operation_log_repository.dart';
import 'package:host_deck/server/features/operation_logs/operation_log_service.dart';

void main() {
  late Directory dataDirectory;
  late DatabaseService database;
  late OperationLogRepository repository;
  late AiAgentOperationLogToolService service;

  Future<AiAgentToolResult> run(Map<String, dynamic> arguments) {
    final normalized = service.normalizeArguments(
      'operation_log_list',
      arguments,
    );
    return service.execute(
      connectionId: 'c1',
      targetKey: 'server:1',
      name: 'operation_log_list',
      arguments: normalized,
    );
  }

  List<Map<String, dynamic>> records(AiAgentToolResult result) =>
      (jsonDecode(result.content)['records'] as List)
          .cast<Map<String, dynamic>>();

  setUp(() async {
    dataDirectory = await Directory.systemTemp.createTemp('hostdeck-oplog-');
    database = DatabaseService(dataDir: dataDirectory.path);
    await database.init();
    repository = OperationLogRepository(database);
    service = AiAgentOperationLogToolService(
      _Delegate(),
      repository,
      OperationLogService(repository),
    );
  });

  tearDown(() async {
    database.close();
    await dataDirectory.delete(recursive: true);
  });

  test('publishes the tool, is approval free and delegates others', () async {
    final names = (await service.resolveSpecs()).map((s) => s.name);
    expect(names, ['delegate_tool', 'operation_log_list']);
    expect(service.requiresApproval('operation_log_list'), isFalse);
    expect(service.requiresApproval('delegate_tool'), isTrue);
    expect(service.summary('delegate_tool'), 'delegate summary');
  });

  test('rejects invalid arguments', () {
    for (final args in <Map<String, dynamic>>[
      {'limit': 0},
      {'limit': 51},
      {'limit': '5'},
      {'status': 'other'},
      {'category': 'a b'},
      {'currentConnectionOnly': 'yes'},
      {'extra': 1},
    ]) {
      expect(
        () => service.normalizeArguments('operation_log_list', args),
        throwsArgumentError,
        reason: '$args',
      );
    }
  });

  test('lists newest first with filters and redaction', () async {
    repository.add(category: 'file', action: 'delete', connectionId: 'c1');
    repository.add(
      category: 'docker',
      action: 'exec',
      target: 'token=abc123 container',
      status: 'failed',
      errorMessage: 'password: hunter2 rejected',
      connectionId: 'c2',
      detail: {'secret': 'x'},
    );

    final all = records(await run({}));
    expect(all.map((r) => r['action']), ['exec', 'delete']);
    expect(all.first['target'], 'token=[redacted] container');
    expect(all.first['error'], 'password: [redacted] rejected');
    expect(all.first['currentConnection'], isFalse);
    expect(all.first.containsKey('detail'), isFalse);
    expect(all.first.containsKey('connectionId'), isFalse);

    expect(records(await run({'status': 'failed'})), hasLength(1));
    expect(records(await run({'category': 'file'})), hasLength(1));
    expect(records(await run({'limit': 1})), hasLength(1));
    final own = records(
      await run({'currentConnectionOnly': true, 'category': 'file'}),
    );
    expect(own.single['action'], 'delete');
    expect(own.single['currentConnection'], isTrue);
  });

  test('records its own usage after reading', () async {
    final result = await run({});
    expect(result.success, isTrue);
    expect(records(result), isEmpty);
    final logged = repository.list();
    expect(logged.single.action, 'operation_log_list');
    expect(logged.single.category, 'aiAgent');
  });

  test('forwards other tools to the delegate', () async {
    final result = await service.execute(
      connectionId: 'c1',
      targetKey: 'server:1',
      name: 'delegate_tool',
      arguments: const {},
    );
    expect(result.content, 'delegated');
  });
}

class _Delegate implements AiAgentToolExecutor {
  @override
  Future<List<ToolSpec>> resolveSpecs({bool refresh = false}) async => const [
    ToolSpec(
      name: 'delegate_tool',
      description: 'delegate',
      inputJsonSchema: {'type': 'object'},
    ),
  ];

  @override
  bool requiresApproval(String name) => true;

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
  }) async => const AiAgentToolResult(
    success: true,
    content: 'delegated',
    summary: 'delegated',
  );
}
