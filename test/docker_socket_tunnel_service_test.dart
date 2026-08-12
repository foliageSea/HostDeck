import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:host_deck/server/core/ssh/ssh_operation_limiter.dart';
import 'package:host_deck/server/core/ssh/ssh_session.dart';
import 'package:host_deck/server/features/docker/docker_socket_tunnel_service.dart';

void main() {
  test('lazily reuses a loopback endpoint per connection', () async {
    final service = DockerSocketTunnelService(
      channelFactory: (_) async => _FakeChannel(),
      disconnectFutureProvider: (_) => Completer<void>().future,
    );
    addTearDown(service.stopAll);
    final session = _FakeSshSession('connection-1');

    final first = await service.endpoint(session);
    final second = await service.endpoint(session);

    expect(second, first);
    expect(first.host, InternetAddress.loopbackIPv4.address);
    expect(first.port, greaterThan(0));
  });

  test('forwards bytes and closes active channel on stopAll', () async {
    late _FakeChannel channel;
    final service = DockerSocketTunnelService(
      channelFactory: (_) async => channel = _FakeChannel(),
      disconnectFutureProvider: (_) => Completer<void>().future,
    );
    final endpoint = await service.endpoint(_FakeSshSession('connection-1'));
    final socket = await Socket.connect(endpoint.host, endpoint.port);
    await Future<void>.delayed(Duration.zero);

    socket.add([1, 2, 3]);
    await expectLater(channel.received.stream, emits([1, 2, 3]));
    channel.send([4, 5]);
    await expectLater(socket, emits([4, 5]));

    await service.stopAll();
    expect(channel.destroyed, isTrue);
  });

  test('SSH disconnect removes the listener', () async {
    final disconnected = Completer<void>();
    final service = DockerSocketTunnelService(
      channelFactory: (_) async => _FakeChannel(),
      disconnectFutureProvider: (_) => disconnected.future,
    );
    final endpoint = await service.endpoint(_FakeSshSession('connection-1'));

    disconnected.complete();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    await expectLater(
      Socket.connect(endpoint.host, endpoint.port),
      throwsA(isA<SocketException>()),
    );
  });
}

class _FakeChannel implements DockerSocketTunnelChannel {
  final _outgoing = StreamController<Uint8List>();
  final received = StreamController<List<int>>();
  final _done = Completer<void>();
  bool destroyed = false;

  void send(List<int> bytes) => _outgoing.add(Uint8List.fromList(bytes));

  @override
  Stream<Uint8List> get stream => _outgoing.stream;

  @override
  StreamSink<List<int>> get sink => received.sink;

  @override
  Future<void> get done => _done.future;

  @override
  Future<void> close() async => destroy();

  @override
  void destroy() {
    if (destroyed) return;
    destroyed = true;
    if (!_done.isCompleted) _done.complete();
    unawaited(_outgoing.close());
    unawaited(received.close());
  }
}

class _FakeSshSession implements SshSession {
  @override
  final String connectionId;

  _FakeSshSession(this.connectionId);

  @override
  String get id => 'session-1';

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
