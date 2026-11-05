import 'dart:async';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:host_deck/server/core/ssh/ssh_service.dart';

void main() {
  test(
    'native transport closes the socket during SSH handshake cancellation',
    () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final accepted = Completer<Socket>();
      final closed = Completer<void>();
      final subscription = server.listen((socket) {
        accepted.complete(socket);
        socket.listen(
          (_) {},
          onDone: closed.complete,
          onError: closed.completeError,
        );
      });
      final service = SshService();
      final connection = service.connect(
        host: '127.0.0.1',
        port: server.port,
        username: 'user',
        requestId: 'native-cancellation',
      );
      final result = expectLater(
        connection,
        throwsA(isA<SshConnectionCancelled>()),
      );
      try {
        await accepted.future.timeout(const Duration(seconds: 5));
        await service.cancelConnect('native-cancellation');
        await result;
        await closed.future.timeout(const Duration(seconds: 5));
        expect(service.getRuntimeSnapshot()['totalClients'], 0);
      } finally {
        if (accepted.isCompleted) (await accepted.future).destroy();
        await subscription.cancel();
        await server.close();
      }
    },
  );

  test('default algorithms prefer AES-128-CTR for bulk transfers', () {
    expect(SshService.defaultAlgorithms.cipher.first, SSHCipherType.aes128ctr);
    expect(SshService.defaultAlgorithms.cipher[1], SSHCipherType.aes256ctr);
  });

  test('default algorithms retain all modern cipher fallbacks', () {
    expect(
      SshService.defaultAlgorithms.cipher,
      unorderedEquals(const SSHAlgorithms().cipher),
    );
  });

  test('default algorithms preserve secure KEX, host key and MAC defaults', () {
    const defaults = SSHAlgorithms();

    expect(SshService.defaultAlgorithms.kex, defaults.kex);
    expect(SshService.defaultAlgorithms.hostkey, defaults.hostkey);
    expect(SshService.defaultAlgorithms.mac, defaults.mac);
  });

  test(
    'disconnecting an unknown connection preserves an empty runtime snapshot',
    () async {
      final service = SshService();

      await service.disconnect('missing-connection');

      expect(service.getRuntimeSnapshot(), {
        'totalClients': 0,
        'totalSessions': 0,
        'clients': <Map<String, dynamic>>[],
        'sessions': <Map<String, dynamic>>[],
      });
    },
  );

  test('authentication failure closes the SSH client', () async {
    final client = _FakeSshClient(
      authenticationError: StateError('authentication failed'),
    );
    final service = _serviceWithClient(client);

    await expectLater(
      service.connect(host: 'example.com', port: 22, username: 'user'),
      throwsStateError,
    );

    expect(client.closeCount, 1);
    expect(service.getRuntimeSnapshot()['totalClients'], 0);
  });

  test('leases track attached channels until released', () async {
    final client = _FakeSshClient();
    final service = _serviceWithClient(client);
    final connectionId = await service.connect(
      host: 'example.com',
      port: 22,
      username: 'user',
    );

    expect(service.leaseCount(connectionId), 0);
    service.attachLease(connectionId, 'status-ws-1');
    service.attachLease(connectionId, 'terminal-ws-1');
    expect(service.leaseCount(connectionId), 2);
    expect(service.lastActivityAt(connectionId), isNotNull);

    service.detachLease(connectionId, 'status-ws-1');
    expect(service.leaseCount(connectionId), 1);
    service.detachLease(connectionId, 'terminal-ws-1');
    expect(service.leaseCount(connectionId), 0);

    await service.disconnect(connectionId);
    expect(service.leaseCount(connectionId), 0);
  });

  test('cancels before the connection request arrives', () async {
    var called = false;
    final service = SshService(
      socketConnector: (_, _) async {
        called = true;
        return _FakeSshSocket();
      },
    );
    await service.cancelConnect('cancel-before-connect');
    await expectLater(
      service.connect(
        host: 'example.com',
        port: 22,
        username: 'user',
        requestId: 'cancel-before-connect',
      ),
      throwsA(isA<SshConnectionCancelled>()),
    );
    expect(called, isFalse);
  });

  test('cancels pending transport and destroys a late socket', () async {
    final pending = Completer<SSHSocket>();
    final socket = _FakeSshSocket();
    final service = SshService(socketConnector: (_, _) => pending.future);
    final connection = service.connect(
      host: 'example.com',
      port: 22,
      username: 'user',
      requestId: 'pending-transport',
    );
    final result = expectLater(
      connection,
      throwsA(isA<SshConnectionCancelled>()),
    );
    await service.cancelConnect('pending-transport');
    await result;
    pending.complete(socket);
    await Future<void>.delayed(Duration.zero);
    expect(socket.destroyCount, 1);
    expect(service.getRuntimeSnapshot()['totalClients'], 0);
  });

  test('cancels authentication and allows a new connection', () async {
    final authentication = Completer<void>();
    final client = _FakeSshClient(authentication: authentication.future);
    final socket = _FakeSshSocket();
    final started = Completer<void>();
    final service = SshService(
      socketConnector: (_, _) async => socket,
      clientFactory: (_, {required username, password, privateKey}) {
        if (!started.isCompleted) started.complete();
        return client;
      },
    );
    final connection = service.connect(
      host: 'example.com',
      port: 22,
      username: 'user',
      requestId: 'pending-authentication',
    );
    final result = expectLater(
      connection,
      throwsA(isA<SshConnectionCancelled>()),
    );
    await started.future;
    await service.cancelConnect('pending-authentication');
    await service.cancelConnect('pending-authentication');
    await result;
    expect(client.closeCount, 1);
    expect(socket.destroyCount, 1);
    authentication.complete();
    await Future<void>.delayed(Duration.zero);
    expect(service.getRuntimeSnapshot()['totalClients'], 0);

    final retryService = _serviceWithClient(_FakeSshClient());
    final retryId = await retryService.connect(
      host: 'example.com',
      port: 22,
      username: 'user',
      requestId: 'new-request',
    );
    await retryService.cancelConnect('new-request');
    expect(retryService.getConnectionMetadata(retryId), isNull);
  });

  test('attaching a lease to an unknown connection is ignored', () {
    final service = SshService();

    service.attachLease('missing-connection', 'lease');
    service.detachLease('missing-connection', 'lease');

    expect(service.leaseCount('missing-connection'), 0);
  });

  test('active disconnect notifies listeners only once', () async {
    final client = _FakeSshClient();
    final service = _serviceWithClient(client);
    var notificationCount = 0;
    service.addDisconnectListener((_) => notificationCount++);
    final connectionId = await service.connect(
      host: 'example.com',
      port: 22,
      username: 'user',
    );

    await service.disconnect(connectionId);
    await Future<void>.delayed(Duration.zero);

    expect(client.closeCount, 1);
    expect(notificationCount, 1);
    expect(service.getRuntimeSnapshot()['totalClients'], 0);
  });
}

SshService _serviceWithClient(_FakeSshClient client) {
  return SshService(
    socketConnector: (_, _) async => _FakeSshSocket(),
    clientFactory: (_, {required username, password, privateKey}) => client,
  );
}

class _FakeSshSocket implements SSHSocket {
  int destroyCount = 0;

  @override
  void destroy() => destroyCount++;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSshClient implements SSHClient {
  final Object? authenticationError;
  final Future<void>? authentication;
  final Completer<void> _done = Completer<void>();
  bool _isClosed = false;
  int closeCount = 0;

  _FakeSshClient({this.authenticationError, this.authentication});

  @override
  Future<void> get authenticated =>
      authentication ??
      (authenticationError == null
          ? Future.value()
          : Future.error(authenticationError!));

  @override
  Future<void> get done => _done.future;

  @override
  bool get isClosed => _isClosed;

  @override
  Future<void> close() async {
    closeCount++;
    _isClosed = true;
    if (!_done.isCompleted) {
      _done.complete();
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
