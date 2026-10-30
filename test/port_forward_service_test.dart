import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:host_deck/server/core/ssh/ssh_service.dart';
import 'package:host_deck/server/features/port_forwards/port_forward_rule.dart';
import 'package:host_deck/server/features/port_forwards/port_forward_service.dart';

void main() {
  late _Ssh ssh;
  late PortForwardService service;

  setUp(() {
    ssh = _Ssh();
    service = PortForwardService(ssh);
  });
  tearDown(() async {
    await service.stopAll();
  });

  const rule = PortForwardRule(
    id: 12,
    name: 'Web',
    protocol: 'http',
    enabled: true,
    bindHost: '0.0.0.0',
    localPort: 0,
    remoteHost: 'internal.test',
    remotePort: 3000,
  );

  test(
    'HTTP uses a private ephemeral listener and releases its SSH lease on disconnect',
    () async {
      await service.start('conn-1', rule);
      final listener = service.listActiveListeners().single;
      expect(listener.host, '127.0.0.1');
      expect(listener.port, greaterThan(0));
      expect(listener.protocol, 'http');
      expect(ssh.leases, {'port-forward:12'});
      expect(service.resolveHttp('12')?.port, listener.port);
      expect(service.resolveHttp('invalid'), isNull);
      await ssh.disconnectListener!('conn-1');
      expect(service.resolveHttp('12'), isNull);
      expect(service.statusFor(12)['status'], 'stopped');
      expect(ssh.leases, isEmpty);
      await expectLater(
        Socket.connect('127.0.0.1', listener.port),
        throwsA(isA<SocketException>()),
      );
    },
  );

  test('stop closes established sockets and SSH channels', () async {
    await service.start('conn-1', rule);
    final upstream = service.resolveHttp('12')!;
    final socket = await Socket.connect(upstream.host, upstream.port);
    final received = socket.toList();
    await ssh.client.opened.future.timeout(const Duration(seconds: 5));
    expect(ssh.client.remoteHost, 'internal.test');
    expect(ssh.client.remotePort, 3000);
    final channel = _Channel();
    ssh.client.channel.complete(channel);
    // Wait for data to traverse the bridge before stopping it.
    final delivered = channel.outbound.stream.first;
    socket.add([1, 2, 3]);
    expect(await delivered.timeout(const Duration(seconds: 5)), [1, 2, 3]);
    expect(service.statusFor(12)['activeConnections'], 1);
    await service.stop(12);
    await received.timeout(const Duration(seconds: 5));
    expect(channel.destroyed, isTrue);
    socket.destroy();
  });

  test(
    'stop during channel creation destroys the channel when it arrives',
    () async {
      await service.start('conn-1', rule);
      final upstream = service.resolveHttp('12')!;
      final socket = await Socket.connect(upstream.host, upstream.port);
      final received = socket.toList();
      await ssh.client.opened.future.timeout(const Duration(seconds: 5));
      await service.stop(12);
      final channel = _Channel();
      ssh.client.channel.complete(channel);
      await channel.closed.future.timeout(const Duration(seconds: 5));
      expect(channel.destroyed, isTrue);
      await received.timeout(const Duration(seconds: 5));
      socket.destroy();
    },
  );

  test('TCP validation and HTTP resolution stay separate', () async {
    expect(
      () => service.validateRule(rule.copyWith(protocol: 'udp')),
      throwsArgumentError,
    );
    expect(
      () => service.validateRule(rule.copyWith(protocol: 'tcp')),
      throwsArgumentError,
    );
    expect(
      () => service.validateRule(rule.copyWith(remotePort: 65536)),
      throwsArgumentError,
    );
    final available = await ServerSocket.bind('127.0.0.1', 0);
    final port = available.port;
    await available.close();
    await service.start(
      'conn-1',
      rule.copyWith(protocol: 'tcp', bindHost: '127.0.0.1', localPort: port),
    );
    expect(service.resolveHttp('12'), isNull);
    expect(service.listActiveListeners().single.port, port);
    expect(ssh.leases, isEmpty);
  });
}

class _Ssh extends SshService {
  final client = _Client();
  final Set<String> leases = {};
  FutureOr<void> Function(String)? disconnectListener;

  @override
  SSHClient? getClient(String connectionId) => client;
  @override
  void addDisconnectListener(FutureOr<void> Function(String) listener) =>
      disconnectListener = listener;
  @override
  void attachLease(String connectionId, String leaseId) => leases.add(leaseId);
  @override
  void detachLease(String connectionId, String leaseId) =>
      leases.remove(leaseId);
}

class _Client implements SSHClient {
  final opened = Completer<void>();
  final channel = Completer<SSHForwardChannel>();
  String? remoteHost;
  int? remotePort;
  @override
  bool get isClosed => false;
  @override
  Future<SSHForwardChannel> forwardLocal(
    String host,
    int port, {
    String localHost = 'localhost',
    int localPort = 0,
  }) {
    remoteHost = host;
    remotePort = port;
    opened.complete();
    return channel.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Channel implements SSHForwardChannel {
  final outbound = StreamController<List<int>>();
  final inbound = StreamController<Uint8List>();
  final closed = Completer<void>();
  bool destroyed = false;
  @override
  Stream<Uint8List> get stream => inbound.stream;
  @override
  StreamSink<List<int>> get sink => outbound.sink;
  @override
  Future<void> get done => closed.future;
  @override
  void destroy() {
    if (destroyed) return;
    destroyed = true;
    closed.complete();
    unawaited(inbound.close());
    unawaited(outbound.close());
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
