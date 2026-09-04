import 'dart:async';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:host_deck/server/core/ssh/ssh_service.dart';
import 'package:host_deck/server/features/port_forwards/secure_browser_tunnel_service.dart';

void main() {
  test('creates a reusable dynamic forward and stops it', () async {
    final sshService = _FakeSshService();
    late SSHDynamicConnectionFilter filter;
    final forward = _FakeDynamicForward();
    final service = SecureBrowserTunnelService(
      sshService,
      forwardFactory: (_, nextFilter) async {
        filter = nextFilter;
        return forward;
      },
    );
    addTearDown(service.stopAll);

    final tunnel = await service.create(connectionId: 'connection-1');
    final reused = await service.create(connectionId: 'connection-1');

    expect(tunnel.bindHost, '127.0.0.1');
    expect(tunnel.bindPort, 49152);
    expect(reused.id, tunnel.id);
    expect(filter('grafana.internal', 3000), isTrue);
    expect(filter('127.0.0.1', 8080), isTrue);
    expect(filter('10.20.30.40', 443), isTrue);
    expect(filter('169.254.169.254', 80), isFalse);
    expect(filter('metadata.google.internal.', 80), isFalse);

    await service.stop(tunnel.id);
    expect(forward.isClosed, isTrue);
    expect(service.list(), isEmpty);
  });

  test('SSH disconnect closes matching dynamic forwards', () async {
    final sshService = _FakeSshService();
    final forward = _FakeDynamicForward();
    final service = SecureBrowserTunnelService(
      sshService,
      forwardFactory: (_, _) async => forward,
    );
    addTearDown(service.stopAll);

    await service.create(connectionId: 'connection-1');
    await sshService.disconnectListener?.call('connection-1');

    expect(forward.isClosed, isTrue);
    expect(service.list(), isEmpty);
  });

  test('rejects an unavailable SSH connection', () async {
    final service = SecureBrowserTunnelService(
      _FakeSshService(connected: false),
    );

    await expectLater(
      service.create(connectionId: 'missing'),
      throwsStateError,
    );
  });
}

class _FakeSshService extends SshService {
  final bool connected;
  final SSHClient _client = _FakeSshClient();
  FutureOr<void> Function(String connectionId)? disconnectListener;

  _FakeSshService({this.connected = true});

  @override
  SSHClient? getClient(String connectionId) => connected ? _client : null;

  @override
  void addDisconnectListener(
    FutureOr<void> Function(String connectionId) listener,
  ) {
    disconnectListener = listener;
  }
}

class _FakeSshClient implements SSHClient {
  @override
  bool get isClosed => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeDynamicForward implements SSHDynamicForward {
  @override
  String get host => '127.0.0.1';

  @override
  int get port => 49152;

  @override
  bool isClosed = false;

  @override
  Future<void> close() async {
    isClosed = true;
  }
}
