import 'dart:async';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:host_deck/server/core/database/database_service.dart';
import 'package:host_deck/server/core/ssh/shared_ssh_session_resolver.dart';
import 'package:host_deck/server/core/ssh/ssh_operation_limiter.dart';
import 'package:host_deck/server/core/ssh/ssh_repository.dart';
import 'package:host_deck/server/core/ssh/ssh_service.dart';
import 'package:host_deck/server/core/ssh/ssh_session.dart';
import 'package:host_deck/server/features/agent/agent_service.dart';
import 'package:host_deck/server/features/ai_agent/ai_agent_tool_service.dart';
import 'package:host_deck/server/features/files/file_item.dart';
import 'package:host_deck/server/features/operation_logs/operation_log_repository.dart';
import 'package:host_deck/server/features/operation_logs/operation_log_service.dart';
import 'package:host_deck/server/features/processes/process_service.dart';
import 'package:host_deck/server/features/system/monitor_service.dart';

void main() {
  late _FakeAgentService agentService;
  late _FakeProcessService processService;
  late _RecordingOperationLogService operationLogs;
  late AiAgentToolService service;

  setUp(() {
    final repository = SshRepository();
    agentService = _FakeAgentService();
    processService = _FakeProcessService();
    operationLogs = _RecordingOperationLogService();
    service = AiAgentToolService(
      _FakeSessionResolver(_FakeSshSession()),
      agentService,
      MonitorService(repository),
      processService,
      operationLogs,
    );
  });

  test('publishes protected directory, delete, and process tools', () async {
    final names = (await service.resolveSpecs()).map((spec) => spec.name);

    expect(
      names,
      containsAll(['directory_list', 'file_delete', 'process_kill']),
    );
    expect(service.requiresApproval('directory_list'), isTrue);
    expect(service.requiresApproval('file_delete'), isTrue);
    expect(service.requiresApproval('process_kill'), isTrue);
    expect(
      () => service.normalizeArguments('process_kill', {'pid': 0}),
      throwsArgumentError,
    );
  });

  test('lists a directory with stable structured output', () async {
    agentService.directoryItems = [
      FileItem(
        filename: 'z.txt',
        longname: '-rw-r--r-- z.txt',
        isDirectory: false,
        size: 12,
      ),
      FileItem(
        filename: 'apps',
        longname: 'drwxr-xr-x apps',
        isDirectory: true,
        size: 0,
      ),
      FileItem(
        filename: '.',
        longname: 'drwxr-xr-x .',
        isDirectory: true,
        size: 0,
      ),
    ];

    final result = await service.execute(
      connectionId: 'connection-1',
      targetKey: 'server:1',
      name: 'directory_list',
      arguments: {'path': '/srv'},
    );

    expect(result.success, isTrue);
    expect(agentService.listedPath, '/srv');
    expect(result.content, contains('"name":"apps"'));
    expect(result.content, contains('"name":"z.txt"'));
    expect(result.content, isNot(contains('"name":"."')));
    expect(operationLogs.successfulActions, contains('directory_list'));
  });

  test('deletes only through the dedicated file operation', () async {
    final result = await service.execute(
      connectionId: 'connection-1',
      targetKey: 'server:1',
      name: 'file_delete',
      arguments: {'path': '/tmp/old.log'},
    );

    expect(result.success, isTrue);
    expect(agentService.deletedPath, '/tmp/old.log');
    expect(result.details, containsPair('operation', 'delete'));
    expect(result.details, containsPair('changed', true));
    expect(operationLogs.successfulActions, contains('file_delete'));
  });

  test('terminates a positive process id with SIGTERM semantics', () async {
    final result = await service.execute(
      connectionId: 'connection-1',
      targetKey: 'server:1',
      name: 'process_kill',
      arguments: {'pid': 4321},
    );

    expect(result.success, isTrue);
    expect(processService.killedPid, 4321);
    expect(result.details, containsPair('signal', 'SIGTERM'));
    expect(result.details, containsPair('operation', 'terminate'));
    expect(operationLogs.successfulActions, contains('process_kill'));
  });
}

class _FakeAgentService extends AgentService {
  List<FileItem> directoryItems = [];
  String? listedPath;
  String? deletedPath;

  _FakeAgentService() : super(SshRepository());

  @override
  Future<List<FileItem>> listDirectory(SshSession session, String path) async {
    listedPath = path;
    return List.of(directoryItems);
  }

  @override
  Future<void> deleteFile(SshSession session, String path) async {
    deletedPath = path;
  }
}

class _FakeProcessService extends ProcessService {
  int? killedPid;

  _FakeProcessService() : super(SshRepository());

  @override
  Future<void> killProcess(SshSession session, int pid) async {
    killedPid = pid;
  }
}

class _RecordingOperationLogService extends OperationLogService {
  final List<String> successfulActions = [];

  _RecordingOperationLogService()
    : super(
        OperationLogRepository(
          DatabaseService(dataDir: '/tmp/hostdeck-ai-tool-test-unused'),
        ),
      );

  @override
  void success({
    required String category,
    required String action,
    String? target,
    Map<String, dynamic>? detail,
    String? connectionId,
  }) {
    successfulActions.add(action);
  }

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
