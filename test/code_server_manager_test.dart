import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:host_deck/server/core/ssh/ssh_service.dart';
import 'package:host_deck/server/features/code_server/code_server_manager.dart';
import 'package:host_deck/server/features/code_server/code_server_models.dart';
import 'package:host_deck/server/features/code_server/ide_package_store.dart';

void main() {
  late HttpServer upstream;
  late Directory tempDir;
  late _FakeSshService ssh;
  late _FakeProvider provider;
  late CodeServerManager manager;

  setUp(() async {
    upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    upstream.listen((request) {
      request.response
        ..statusCode = 200
        ..write('{"status":"alive"}');
      request.response.close();
    });
    tempDir = await Directory.systemTemp.createTemp('hostdeck_cs_manager_');
    ssh = _FakeSshService(upstream.port);
    provider = _FakeProvider();
    manager = CodeServerManager(
      sshService: ssh,
      provider: provider,
      packages: IdePackageStore(tempDir),
    );
  });

  tearDown(() async {
    await manager.dispose();
    await upstream.close(force: true);
    await tempDir.delete(recursive: true);
  });

  test(
    'stop from a reconnected connection stops the running session',
    () async {
      ssh.online('old');
      final started = await manager.start('old');
      expect(started.state, IdeSessionState.running);

      // 同一目标重连得到新 connectionId，status 会复用旧会话。
      ssh.online('new');
      expect(manager.sessionFor('new')?.id, started.id);

      final stopped = await manager.stop('new');

      expect(stopped.id, started.id);
      expect(stopped.state, IdeSessionState.stopped);
      expect(provider.stops.single, (connectionId: 'old', pid: 4242));
      expect(await manager.resolve(started.id), isNull);
    },
  );

  test(
    'a disconnected session stays stoppable from a new connection',
    () async {
      ssh.online('old');
      final started = await manager.start('old');

      ssh.online('new');
      await ssh.disconnect('old');

      final orphan = manager.sessionFor('new');
      expect(orphan?.id, started.id);
      expect(orphan?.state, IdeSessionState.error);

      await manager.stop('new');

      // 旧连接已断开，改用新连接结束同一目标机上的远端进程。
      expect(provider.stops.single, (connectionId: 'new', pid: 4242));
    },
  );

  test(
    'start reclaims an orphaned process before launching a new one',
    () async {
      ssh.online('old');
      await manager.start('old');

      ssh.online('new');
      await ssh.disconnect('old');

      final restarted = await manager.start('new');

      expect(restarted.state, IdeSessionState.running);
      expect(provider.stops.single, (connectionId: 'new', pid: 4242));
      expect(provider.starts, ['old', 'new']);
    },
  );
}

class _FakeProvider implements RemoteIdeProvider {
  final List<String> starts = [];
  final List<({String connectionId, int pid})> stops = [];

  @override
  Future<IdePreflight> preflight(
    String connectionId, {
    String? expectedVersion,
  }) async => const IdePreflight(
    arch: 'amd64',
    libc: 'glibc 2.39',
    diskFreeBytes: 1 << 40,
    installedVersion: '4.143.1',
    issues: [],
  );

  @override
  Future<void> install(
    String connectionId,
    IdePackage package, {
    void Function(int received, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {}

  @override
  Future<IdeLaunch> start(
    String connectionId, {
    required String sessionId,
    required String hostKey,
    required String version,
  }) async {
    starts.add(connectionId);
    return IdeLaunch(
      port: 18090,
      pid: 4242,
      version: version,
      sessionFile: '/tmp/$sessionId.json',
    );
  }

  @override
  Future<void> stop(
    String connectionId, {
    required String sessionId,
    required int pid,
  }) async {
    stops.add((connectionId: connectionId, pid: pid));
  }
}

class _FakeSshService extends SshService {
  _FakeSshService(this.upstreamPort);

  final int upstreamPort;
  final Set<String> _connected = {};
  final List<FutureOr<void> Function(String)> _listeners = [];

  void online(String connectionId) => _connected.add(connectionId);

  @override
  Future<void> disconnect(String connectionId) async {
    _connected.remove(connectionId);
    for (final listener in _listeners) {
      await listener(connectionId);
    }
  }

  @override
  void addDisconnectListener(
    FutureOr<void> Function(String connectionId) listener,
  ) {
    _listeners.add(listener);
  }

  // 所有连接指向同一台目标机，hostKey 相同。
  @override
  SshConnectionMetadata? metadataFor(String connectionId) =>
      _connected.contains(connectionId)
      ? const SshConnectionMetadata(host: '10.0.0.5', port: 22, username: 'dev')
      : null;

  @override
  SSHClient? getClient(String connectionId) => _connected.contains(connectionId)
      ? _LoopbackSshClient(upstreamPort)
      : null;

  @override
  void attachLease(String connectionId, String leaseId) {}

  @override
  void detachLease(String connectionId, String leaseId) {}

  @override
  void touch(String connectionId) {}
}

class _LoopbackSshClient implements SSHClient {
  _LoopbackSshClient(this.port);

  final int port;
  final Completer<void> _done = Completer<void>();

  @override
  Future<SSHForwardChannel> forwardLocal(
    String remoteHost,
    int remotePort, {
    String localHost = 'localhost',
    int localPort = 0,
  }) async {
    final socket = await Socket.connect(InternetAddress.loopbackIPv4, port);
    return _SocketForwardChannel(socket);
  }

  @override
  Future<void> get done => _done.future;

  @override
  bool get isClosed => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SocketForwardChannel implements SSHForwardChannel {
  _SocketForwardChannel(this._socket);

  final Socket _socket;

  @override
  Stream<Uint8List> get stream => _socket;

  @override
  StreamSink<List<int>> get sink => _socket;

  @override
  Future<void> get done => _socket.done;

  @override
  Future<void> close() async => _socket.close();

  @override
  void destroy() => _socket.destroy();
}
