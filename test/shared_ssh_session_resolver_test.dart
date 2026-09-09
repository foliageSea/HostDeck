import 'dart:async';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:host_deck/server/core/ssh/shared_ssh_session_resolver.dart';
import 'package:host_deck/server/core/ssh/ssh_operation_limiter.dart';
import 'package:host_deck/server/core/ssh/ssh_service.dart';
import 'package:host_deck/server/core/ssh/ssh_session.dart';
import 'package:shelf/shelf.dart';

void main() {
  test(
    'passes the configured purpose when creating a shared session',
    () async {
      final session = _FakeSshSession();
      final sshService = _FakeSshService(session);
      final resolver = SharedSshSessionResolver(
        sshService,
        type: SharedSshSessionType.sftp,
        purpose: SshSessionPurpose.fileManagement,
      );

      expect(await resolver.createForConnection('connection-1'), same(session));
      expect(sshService.createdPurpose, SshSessionPurpose.fileManagement);
    },
  );

  test('aggregates purposes when resolvers reuse the same session', () async {
    final session = _FakeSshSession();
    final sshService = _FakeSshService(session);
    final fileResolver = SharedSshSessionResolver(
      sshService,
      type: SharedSshSessionType.sftp,
      purpose: SshSessionPurpose.fileManagement,
    );
    final dockerResolver = SharedSshSessionResolver(
      sshService,
      type: SharedSshSessionType.sftp,
      purpose: SshSessionPurpose.docker,
    );
    final request = Request(
      'GET',
      Uri.parse('http://localhost/resource?sessionId=session-1'),
    );

    expect(await fileResolver.resolveFromRequest(request), same(session));
    expect(await dockerResolver.resolveFromRequest(request), same(session));
    expect(sshService.purposes, {
      SshSessionPurpose.fileManagement,
      SshSessionPurpose.docker,
    });
  });
}

class _FakeSshService extends SshService {
  final SshSession session;
  final Set<SshSessionPurpose> purposes = {};
  SshSessionPurpose? createdPurpose;

  _FakeSshService(this.session);

  @override
  SshSession? getSession(String id) => id == session.id ? session : null;

  @override
  bool addSessionPurpose(String id, SshSessionPurpose purpose) {
    if (id != session.id) return false;
    purposes.add(purpose);
    return true;
  }

  @override
  Future<SshSession> createSftpSession(
    String connectionId, {
    required SshSessionPurpose purpose,
  }) async {
    createdPurpose = purpose;
    purposes.add(purpose);
    return session;
  }
}

class _FakeSshSession implements SshSession {
  @override
  String get id => 'session-1';
  @override
  String get connectionId => 'connection-1';
  @override
  SSHClient get client => throw UnimplementedError();
  @override
  SSHSession? get shell => null;
  @override
  final SshOperationLimiter operationLimiter = SshOperationLimiter(
    maxConcurrentOperations: 1,
  );
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
