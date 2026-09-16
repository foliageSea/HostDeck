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

  test(
    'reuses an in-flight session creation for the same connection',
    () async {
      final session = _FakeSshSession();
      final creation = Completer<SshSession>();
      final sshService = _FakeSshService(session, creation: creation);
      final resolver = SharedSshSessionResolver(
        sshService,
        type: SharedSshSessionType.sftp,
        purpose: SshSessionPurpose.aiAgent,
      );

      final first = resolver.createForConnection('connection-1');
      final second = resolver.createForConnection('connection-1');
      creation.complete(session);

      expect(await first, same(session));
      expect(await second, same(session));
      expect(sshService.createCount, 1);
    },
  );

  test(
    'closes a pending session and treats repeated close as success',
    () async {
      final session = _FakeSshSession();
      final creation = Completer<SshSession>();
      final sshService = _FakeSshService(session, creation: creation);
      final resolver = SharedSshSessionResolver(
        sshService,
        type: SharedSshSessionType.sftp,
        purpose: SshSessionPurpose.aiAgent,
      );
      final request = Request(
        'DELETE',
        Uri.parse('http://localhost/session?connectionId=connection-1'),
      );

      final pendingSession = resolver.createForConnection('connection-1');
      final pendingClose = resolver.closeFromRequest(request);
      creation.complete(session);

      await pendingSession;
      await pendingClose;
      await resolver.closeFromRequest(request);
      expect(sshService.closedSessionIds, ['session-1']);
    },
  );

  test(
    'does not close a replacement created while closing pending work',
    () async {
      final firstSession = _FakeSshSession(id: 'session-1');
      final secondSession = _FakeSshSession(id: 'session-2');
      final firstCreation = Completer<SshSession>();
      final sshService = _FakeSshService(
        firstSession,
        creation: firstCreation,
        subsequentSession: secondSession,
      );
      final resolver = SharedSshSessionResolver(
        sshService,
        type: SharedSshSessionType.sftp,
        purpose: SshSessionPurpose.aiAgent,
      );
      final request = Request(
        'DELETE',
        Uri.parse('http://localhost/session?connectionId=connection-1'),
      );

      final first = resolver.createForConnection('connection-1');
      final close = resolver.closeFromRequest(request);
      final replacement = resolver.createForConnection('connection-1');
      firstCreation.complete(firstSession);

      expect(await first, same(firstSession));
      expect(await replacement, same(secondSession));
      await close;
      expect(sshService.closedSessionIds, ['session-1']);
      expect(
        await resolver.createForConnection('connection-1'),
        same(secondSession),
      );
      expect(sshService.createCount, 2);
    },
  );
}

class _FakeSshService extends SshService {
  final SshSession session;
  final SshSession? subsequentSession;
  final Set<SshSessionPurpose> purposes = {};
  final Completer<SshSession>? creation;
  final List<String> closedSessionIds = [];
  SshSessionPurpose? createdPurpose;
  int createCount = 0;

  _FakeSshService(this.session, {this.creation, this.subsequentSession});

  @override
  SshSession? getSession(String id) {
    if (id == session.id) return session;
    if (id == subsequentSession?.id) return subsequentSession;
    return null;
  }

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
    createCount += 1;
    createdPurpose = purpose;
    purposes.add(purpose);
    if (createCount == 1 && creation != null) return creation!.future;
    return subsequentSession ?? session;
  }

  @override
  Future<void> closeSession(String id) async {
    closedSessionIds.add(id);
  }
}

class _FakeSshSession implements SshSession {
  final String _id;

  _FakeSshSession({String id = 'session-1'}) : _id = id;

  @override
  String get id => _id;
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
