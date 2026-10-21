import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:host_deck/server/core/ssh/ssh_connection_handle.dart';
import 'package:host_deck/server/core/ssh/ssh_operation_limiter.dart';
import 'package:host_deck/server/core/ssh/ssh_repository.dart';
import 'package:host_deck/server/core/ssh/ssh_session.dart';
import 'package:host_deck/server/features/docker/docker_compose_service.dart';

void main() {
  test(
    'reports compose as available through bash when dash cannot load profile',
    () async {
      final session = _FakeSshSession(
        _FakeSshClient(
          (command) => command.startsWith('sh -lc ')
              ? _result(2, 'Bad substitution')
              : _result(0, ''),
        ),
      );
      final repository = _FakeSshRepository(
        (command) => command.startsWith('bash -lc ')
            ? (output: 'Docker Compose version v2.29.1', exitCode: 0)
            : (output: 'sh: Bad substitution', exitCode: 2),
      );
      final service = DockerComposeService(repository);

      final availability = await service.inspectAvailability(session);

      expect(availability.available, isTrue);
      expect(availability.command, 'docker compose');
      expect(availability.detail, isNull);
    },
  );

  test('surfaces the remote failure instead of a bare false', () async {
    final session = _FakeSshSession(
      _FakeSshClient((command) => _result(0, '')),
    );
    final repository = _FakeSshRepository(
      (command) => (output: 'bash: docker: command not found', exitCode: 127),
    );
    final service = DockerComposeService(repository);

    final availability = await service.inspectAvailability(session);

    expect(availability.available, isFalse);
    expect(availability.detail, contains('command not found'));
  });

  test('caches the resolved compose command per connection', () async {
    final session = _FakeSshSession(
      _FakeSshClient((command) => _result(0, '')),
    );
    final repository = _FakeSshRepository(
      (command) => (output: 'Docker Compose version v2.29.1', exitCode: 0),
    );
    final service = DockerComposeService(repository);

    await service.inspectAvailability(session);
    final callsAfterFirst = repository.commands.length;
    await service.inspectAvailability(session);

    expect(repository.commands, hasLength(callsAfterFirst));

    service.invalidateCache(session.connectionId);
    await service.inspectAvailability(session);
    expect(repository.commands.length, greaterThan(callsAfterFirst));
  });

  test('streams project actions through the resolved shell', () async {
    final client = _FakeSshClient(
      (command) => command.startsWith('sh -lc ')
          ? _result(2, 'Bad substitution')
          : _result(0, ''),
    );
    final session = _FakeSshSession(client);
    final repository = _FakeSshRepository(
      (command) => (output: 'Docker Compose version v2.29.1', exitCode: 0),
    );
    final service = DockerComposeService(repository);

    await expectLater(
      service
          .streamComposeProjectAction(
            session,
            action: 'up',
            projectName: 'website',
            configFiles: ['/opt/website/compose.yml'],
          )
          .drain<void>(),
      throwsA(isA<UnimplementedError>()),
    );

    final executed = client.executedCommands.last;
    expect(executed, startsWith("bash -lc '"));
    expect(executed, contains('docker'));
  });
}

SSHRunResult _result(int exitCode, String stderr) => SSHRunResult(
  output: Uint8List(0),
  stdout: Uint8List(0),
  stderr: Uint8List.fromList(stderr.codeUnits),
  exitCode: exitCode,
  exitSignal: null,
);

class _FakeSshRepository extends SshRepository {
  static const _marker = '__HOST_DECK_COMPOSE_STATUS__';

  final ({String output, int exitCode}) Function(String command) handler;
  final List<String> commands = [];

  _FakeSshRepository(this.handler);

  @override
  Future<String> exec(SshOperationContext session, String command) async {
    commands.add(command);
    final outcome = handler(command);
    return '${outcome.output}\n$_marker:${outcome.exitCode}';
  }
}

class _FakeSshClient implements SSHClient {
  final SSHRunResult Function(String command) handler;
  final List<String> executedCommands = [];

  _FakeSshClient(this.handler);

  @override
  Future<SSHSession> execute(
    String command, {
    SSHPtyConfig? pty,
    SSHX11Config? x11,
    Map<String, String>? environment,
  }) async {
    executedCommands.add(command);
    throw UnimplementedError('execute');
  }

  @override
  Future<SSHRunResult> runWithResult(
    String command, {
    bool runInPty = false,
    bool stdout = true,
    bool stderr = true,
    Map<String, String>? environment,
  }) async => handler(command);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSshSession implements SshSession {
  @override
  final SSHClient client;
  @override
  final SshOperationLimiter operationLimiter = SshOperationLimiter(
    maxConcurrentOperations: 4,
  );

  _FakeSshSession(this.client);

  @override
  String get id => 'session-1';
  @override
  String get connectionId => 'connection-1';
  @override
  SSHSession? get shell => null;
  @override
  Stream<String> get output => const Stream.empty();
  @override
  StreamController<String> get outputController => StreamController.broadcast();
  @override
  Future<SshOperationPermit> acquireOperation() => operationLimiter.acquire();
  @override
  Future<T> runOperation<T>(FutureOr<T> Function() action) =>
      operationLimiter.run(action);
  @override
  Future<SftpClient> sftp() => throw UnimplementedError();
  @override
  Future<void> close() async {}
}
