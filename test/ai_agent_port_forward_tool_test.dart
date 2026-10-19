import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:dartssh2/dartssh2.dart';

import 'package:host_deck/server/core/database/database_service.dart';
import 'package:host_deck/server/core/ssh/shared_ssh_session_resolver.dart';
import 'package:host_deck/server/core/ssh/ssh_repository.dart';
import 'package:host_deck/server/core/ssh/ssh_service.dart';
import 'package:host_deck/server/core/ssh/ssh_session.dart';
import 'package:host_deck/server/core/ssh/ssh_operation_limiter.dart';
import 'package:host_deck/server/features/agent/agent_service.dart';
import 'package:host_deck/server/features/ai_agent/ai_agent_tool_service.dart';
import 'package:host_deck/server/features/operation_logs/operation_log_repository.dart';
import 'package:host_deck/server/features/operation_logs/operation_log_service.dart';
import 'package:host_deck/server/features/port_forwards/port_forward_repository.dart';
import 'package:host_deck/server/features/port_forwards/port_forward_rule.dart';
import 'package:host_deck/server/features/port_forwards/port_forward_service.dart';
import 'package:host_deck/server/features/processes/process_service.dart';
import 'package:host_deck/server/features/system/monitor_service.dart';

void main() {
  late Directory dataDirectory;
  late DatabaseService database;
  late PortForwardRepository repository;
  late _FakePortForwardService forwards;
  late AiAgentToolService service;

  setUp(() async {
    dataDirectory = await Directory.systemTemp.createTemp(
      'hostdeck-ai-forward-',
    );
    database = DatabaseService(dataDir: dataDirectory.path);
    await database.init();
    repository = PortForwardRepository(database);
    forwards = _FakePortForwardService();
    service = AiAgentToolService(
      _FakeSessionResolver(_FakeSshSession()),
      AgentService(SshRepository()),
      MonitorService(SshRepository()),
      ProcessService(SshRepository()),
      _RecordingOperationLogService(database),
      repository,
      forwards,
    );
  });

  tearDown(() async {
    database.close();
    await dataDirectory.delete(recursive: true);
  });

  test('publishes port forward tools with approval boundaries', () async {
    final names = (await service.resolveSpecs()).map((spec) => spec.name);

    expect(
      names,
      containsAll([
        'port_forward_create',
        'port_forward_start',
        'port_forward_list',
        'port_forward_status',
        'port_forward_stop',
        'port_forward_delete',
      ]),
    );
    expect(service.requiresApproval('port_forward_list'), isFalse);
    expect(service.requiresApproval('port_forward_status'), isFalse);
    expect(service.requiresApproval('port_forward_create'), isTrue);
    expect(service.requiresApproval('port_forward_start'), isTrue);
    expect(service.requiresApproval('port_forward_stop'), isTrue);
    expect(service.requiresApproval('port_forward_delete'), isTrue);
  });

  test('creates, inspects, stops, and deletes a port forward', () async {
    final created = await service.execute(
      connectionId: 'connection-1',
      targetKey: 'server:1',
      name: 'port_forward_create',
      arguments: {
        'name': 'Grafana',
        'localPort': 18080,
        'remoteHost': 'grafana.internal',
        'remotePort': 3000,
      },
    );

    expect(created.success, isTrue);
    final createdRule = created.details['structured'] as Map<String, dynamic>;
    final ruleId = createdRule['id'] as int;
    expect(createdRule, containsPair('bindHost', '127.0.0.1'));
    expect(createdRule, containsPair('status', 'running'));
    expect(forwards.active, contains(ruleId));

    final status = await service.execute(
      connectionId: 'connection-1',
      targetKey: 'server:1',
      name: 'port_forward_status',
      arguments: {'ruleId': ruleId},
    );
    expect(status.success, isTrue);
    expect(
      status.details['structured'],
      containsPair('connectionId', 'connection-1'),
    );

    final listed = await service.execute(
      connectionId: 'connection-1',
      targetKey: 'server:1',
      name: 'port_forward_list',
      arguments: {},
    );
    expect(listed.success, isTrue);
    expect(
      listed.details['structured'],
      containsPair('forwards', contains(containsPair('id', ruleId))),
    );

    final deleteWhileRunning = await service.execute(
      connectionId: 'connection-1',
      targetKey: 'server:1',
      name: 'port_forward_delete',
      arguments: {'ruleId': ruleId},
    );
    expect(deleteWhileRunning.success, isFalse);
    expect(repository.getRule(ruleId), isNotNull);

    final stopped = await service.execute(
      connectionId: 'connection-1',
      targetKey: 'server:1',
      name: 'port_forward_stop',
      arguments: {'ruleId': ruleId},
    );
    expect(stopped.success, isTrue);
    expect(forwards.active, isNot(contains(ruleId)));
    expect(stopped.details['structured'], containsPair('status', 'stopped'));

    final restarted = await service.execute(
      connectionId: 'connection-1',
      targetKey: 'server:1',
      name: 'port_forward_start',
      arguments: {'ruleId': ruleId},
    );
    expect(restarted.success, isTrue);
    expect(restarted.details['structured'], containsPair('status', 'running'));

    final stoppedAgain = await service.execute(
      connectionId: 'connection-1',
      targetKey: 'server:1',
      name: 'port_forward_stop',
      arguments: {'ruleId': ruleId},
    );
    expect(stoppedAgain.success, isTrue);

    final deleted = await service.execute(
      connectionId: 'connection-1',
      targetKey: 'server:1',
      name: 'port_forward_delete',
      arguments: {'ruleId': ruleId},
    );
    expect(deleted.success, isTrue);
    expect(repository.getRule(ruleId), isNull);
  });

  test('rejects invalid arguments before creating a rule', () async {
    expect(
      () => service.normalizeArguments('port_forward_create', {
        'name': 'bad',
        'localPort': 0,
        'remoteHost': 'remote',
        'remotePort': 80,
      }),
      throwsArgumentError,
    );
    expect(
      () => service.normalizeArguments('port_forward_create', {
        'name': 'bad',
        'localPort': 8080,
        'remoteHost': 'remote host',
        'remotePort': 80,
      }),
      throwsArgumentError,
    );
    expect(repository.getAllRules(), isEmpty);
  });

  test('removes a rule when starting the forward fails', () async {
    forwards.failStart = true;

    final result = await service.execute(
      connectionId: 'connection-1',
      targetKey: 'server:1',
      name: 'port_forward_create',
      arguments: {
        'name': 'Broken',
        'localPort': 18081,
        'remoteHost': 'remote.internal',
        'remotePort': 8080,
      },
    );

    expect(result.success, isFalse);
    expect(repository.getAllRules(), isEmpty);
  });
}

class _FakePortForwardService extends PortForwardService {
  final Set<int> active = {};
  final Map<int, String> connections = {};
  bool failStart = false;

  _FakePortForwardService() : super(SshService());

  @override
  Future<void> start(String connectionId, PortForwardRule rule) async {
    if (failStart) throw StateError('Unable to start forward.');
    active.add(rule.id!);
    connections[rule.id!] = connectionId;
  }

  @override
  Future<void> stop(int ruleId) async {
    active.remove(ruleId);
    connections.remove(ruleId);
  }

  @override
  Map<String, dynamic> statusFor(int ruleId) {
    final connectionId = connections[ruleId];
    return {
      'status': connectionId == null ? 'stopped' : 'running',
      'error': null,
      'connectionId': connectionId,
      if (connectionId != null) 'startedAt': 1,
      if (connectionId != null) 'activeConnections': 0,
    };
  }
}

class _RecordingOperationLogService extends OperationLogService {
  _RecordingOperationLogService(DatabaseService database)
    : super(OperationLogRepository(database));

  @override
  void success({
    required String category,
    required String action,
    String? target,
    Map<String, dynamic>? detail,
    String? connectionId,
  }) {}

  @override
  void failure({
    required String category,
    required String action,
    String? target,
    Map<String, dynamic>? detail,
    String? connectionId,
    required Object error,
  }) {}
}

class _FakeSessionResolver extends SharedSshSessionResolver {
  final SshSession session;

  _FakeSessionResolver(this.session)
    : super(
        SshService(),
        type: SharedSshSessionType.sftp,
        purpose: SshSessionPurpose.aiAgent,
      );

  @override
  Future<SshSession> createForConnection(String connectionId) async => session;
}

class _FakeSshSession implements SshSession {
  @override
  SSHClient get client => throw UnimplementedError();

  @override
  String get connectionId => 'connection-1';

  @override
  String get id => 'session-1';

  @override
  final SshOperationLimiter operationLimiter = SshOperationLimiter(
    maxConcurrentOperations: 4,
  );

  @override
  Stream<String> get output => const Stream.empty();

  @override
  StreamController<String> get outputController => StreamController.broadcast();

  @override
  SSHSession? get shell => null;

  @override
  Future<SftpClient> sftp() => throw UnimplementedError();

  @override
  Future<SshOperationPermit> acquireOperation() => operationLimiter.acquire();

  @override
  Future<T> runOperation<T>(FutureOr<T> Function() action) {
    return operationLimiter.run(action);
  }

  @override
  Future<void> close() async {}
}
