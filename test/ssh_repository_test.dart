import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:host_deck/server/core/ssh/ssh_operation_limiter.dart';
import 'package:host_deck/server/core/ssh/ssh_repository.dart';
import 'package:host_deck/server/core/ssh/ssh_session.dart';

void main() {
  for (final operation
      in <String, Future<void> Function(SshRepository, SshSession)>{
        'copy': (repository, session) =>
            repository.copy(session, '/source', '/target'),
        'delete': (repository, session) =>
            repository.delete(session, '/target'),
      }.entries) {
    test('${operation.key} reports a non-zero remote exit code', () async {
      final session = _FakeSshSession(
        _FakeSshClient(
          SSHRunResult(
            output: Uint8List.fromList('permission denied'.codeUnits),
            stdout: Uint8List(0),
            stderr: Uint8List.fromList('permission denied'.codeUnits),
            exitCode: 1,
            exitSignal: null,
          ),
        ),
      );

      await expectLater(
        operation.value(SshRepository(), session),
        throwsA(
          isA<Exception>().having(
            (error) => error.toString(),
            'message',
            contains('permission denied'),
          ),
        ),
      );
    });
  }
}

class _FakeSshClient implements SSHClient {
  final SSHRunResult result;

  _FakeSshClient(this.result);

  @override
  Future<SSHRunResult> runWithResult(
    String command, {
    bool runInPty = false,
    bool stdout = true,
    bool stderr = true,
    Map<String, String>? environment,
  }) async => result;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSshSession implements SshSession {
  @override
  final SSHClient client;
  @override
  final SshOperationLimiter operationLimiter = SshOperationLimiter(
    maxConcurrentOperations: 1,
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
