import 'dart:async';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:host_deck/server/core/ssh/ssh_service.dart';

void main() {
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
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSshClient implements SSHClient {
  final Object? authenticationError;
  final Completer<void> _done = Completer<void>();
  bool _isClosed = false;
  int closeCount = 0;

  _FakeSshClient({this.authenticationError});

  @override
  Future<void> get authenticated => authenticationError == null
      ? Future.value()
      : Future.error(authenticationError!);

  @override
  Future<void> get done => _done.future;

  @override
  bool get isClosed => _isClosed;

  @override
  void close() {
    closeCount++;
    _isClosed = true;
    if (!_done.isCompleted) {
      _done.complete();
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
