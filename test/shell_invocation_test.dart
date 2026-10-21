import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:host_deck/server/core/ssh/shell_invocation.dart';
import 'package:host_deck/server/core/ssh/ssh_operation_limiter.dart';
import 'package:host_deck/server/core/ssh/ssh_session.dart';

void main() {
  test(
    'falls back to bash when the dash login shell cannot read profile',
    () async {
      final session = _FakeSshSession(
        _FakeSshClient(
          (command) => command.startsWith('sh -lc ')
              ? _result(2, 'Bad substitution')
              : _result(0, ''),
        ),
      );
      final resolver = ShellInvocationResolver();

      final invocation = await resolver.resolve(session);

      expect(invocation.prefix, 'bash -lc');
      expect(invocation.loadsProfile, isTrue);
    },
  );

  test('keeps sh -lc when the login shell works', () async {
    final session = _FakeSshSession(
      _FakeSshClient((command) => _result(0, '')),
    );
    final resolver = ShellInvocationResolver();

    expect((await resolver.resolve(session)).prefix, 'sh -lc');
  });

  test('drops the profile when no login shell starts', () async {
    final session = _FakeSshSession(
      _FakeSshClient(
        (command) => command.startsWith('sh -c ')
            ? _result(0, '')
            : _result(2, 'Bad substitution'),
      ),
    );
    final resolver = ShellInvocationResolver();

    final invocation = await resolver.resolve(session);

    expect(invocation.prefix, 'sh -c');
    expect(invocation.loadsProfile, isFalse);
  });

  test('probes once per connection and reuses the cached result', () async {
    final client = _FakeSshClient(
      (command) => command.startsWith('sh -lc ')
          ? _result(2, 'Bad substitution')
          : _result(0, ''),
    );
    final session = _FakeSshSession(client);
    final resolver = ShellInvocationResolver();

    await Future.wait([resolver.resolve(session), resolver.resolve(session)]);
    await resolver.resolve(session);

    expect(client.commands, hasLength(2));
    expect(resolver.cached(session.connectionId)?.prefix, 'bash -lc');
  });

  test('re-probes after invalidating a connection', () async {
    final client = _FakeSshClient((command) => _result(0, ''));
    final session = _FakeSshSession(client);
    final resolver = ShellInvocationResolver();

    await resolver.resolve(session);
    resolver.invalidate(session.connectionId);
    expect(resolver.cached(session.connectionId), isNull);

    await resolver.resolve(session);
    expect(client.commands, hasLength(2));
  });

  test('does not cache a probe that was invalidated mid-flight', () async {
    final client = _BlockingSshClient();
    final session = _FakeSshSession(client);
    final resolver = ShellInvocationResolver();

    final inFlight = resolver.resolve(session);
    await Future<void>.delayed(Duration.zero);
    expect(client.commands, isNotEmpty);

    resolver.invalidate(session.connectionId);
    client.release(_result(0, ''));

    expect((await inFlight).prefix, 'sh -lc');
    expect(resolver.cached(session.connectionId), isNull);
  });

  test('uses a plain shell without caching when no candidate starts', () async {
    final client = _FakeSshClient((command) => _result(2, 'Bad substitution'));
    final resolver = ShellInvocationResolver();

    final invocation = await resolver.resolve(_FakeSshSession(client));

    expect(invocation.prefix, 'sh -c');
    expect(invocation.loadsProfile, isFalse);
    expect(resolver.cached('connection-1'), isNull);
    expect(client.commands, hasLength(3));
  });

  test('re-probes after a total probe failure', () async {
    final client = _FakeSshClient((command) => _result(2, 'Bad substitution'));
    final resolver = ShellInvocationResolver();
    final session = _FakeSshSession(client);

    await resolver.resolve(session);
    await resolver.resolve(session);

    expect(client.commands, hasLength(6));
  });

  test('wrap keeps single quotes intact', () {
    const invocation = ShellInvocation('bash -lc');

    expect(invocation.wrap("echo 'hi'"), "bash -lc 'echo '\\''hi'\\'''");
  });
}

SSHRunResult _result(int exitCode, String stderr) => SSHRunResult(
  output: Uint8List(0),
  stdout: Uint8List(0),
  stderr: Uint8List.fromList(stderr.codeUnits),
  exitCode: exitCode,
  exitSignal: null,
);

class _FakeSshClient implements SSHClient {
  final SSHRunResult Function(String command) handler;
  final List<String> commands = [];

  _FakeSshClient(this.handler);

  @override
  Future<SSHRunResult> runWithResult(
    String command, {
    bool runInPty = false,
    bool stdout = true,
    bool stderr = true,
    Map<String, String>? environment,
  }) async {
    commands.add(command);
    return handler(command);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Holds the first probe open until [release] is called.
class _BlockingSshClient implements SSHClient {
  final List<String> commands = [];
  final Completer<SSHRunResult> _gate = Completer<SSHRunResult>();

  void release(SSHRunResult result) {
    if (!_gate.isCompleted) {
      _gate.complete(result);
    }
  }

  @override
  Future<SSHRunResult> runWithResult(
    String command, {
    bool runInPty = false,
    bool stdout = true,
    bool stderr = true,
    Map<String, String>? environment,
  }) {
    commands.add(command);
    return _gate.future;
  }

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
