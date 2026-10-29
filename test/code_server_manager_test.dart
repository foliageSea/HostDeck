import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:host_deck/server/features/code_server/code_server_controller.dart';
import 'package:host_deck/server/routes/code_server_routes.dart';
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
  test(
    'uninstall stops a running session via reconnect and clears leases and proxy',
    () async {
      ssh.online('old');
      final started = await manager.start('old');
      ssh.online('new');
      await ssh.disconnect('old');
      await manager.preflight('new');
      await manager.uninstall('new');
      expect(provider.stops.single, (connectionId: 'new', pid: 4242));
      expect(provider.uninstalls, ['new']);
      expect(manager.sessionFor('new'), isNull);
      expect(await manager.resolve(started.id), isNull);
      expect(ssh.leases, isEmpty);
      final probes = provider.probes;
      await manager.preflight('new');
      expect(provider.probes, probes + 1);
    },
  );

  test(
    'uninstall failure to stop aborts deletion and retains pid for retry',
    () async {
      ssh.online('old');
      await manager.start('old');
      ssh.online('new');
      provider.failStop = true;
      await expectLater(manager.uninstall('new'), throwsStateError);
      expect(provider.uninstalls, isEmpty);
      expect(manager.sessionFor('old')?.state, IdeSessionState.error);
      provider.failStop = false;
      await manager.uninstall('new');
      expect(provider.stops, hasLength(2));
      expect(provider.uninstalls, ['new']);
      expect(ssh.leases, isEmpty);
    },
  );

  test(
    'uninstall locks all connections for target and releases lock after deletion fails',
    () async {
      ssh.online('old');
      ssh.online('new');
      provider.uninstallGate = Completer<void>();
      provider.failUninstall = true;
      final uninstall = manager.uninstall('old');
      final failed = expectLater(uninstall, throwsStateError);
      await Future<void>.delayed(Duration.zero);
      await expectLater(manager.start('new'), throwsStateError);
      await expectLater(
        manager.install('new', packageId: 'unused'),
        throwsStateError,
      );
      await expectLater(manager.stop('new'), throwsStateError);
      await expectLater(manager.uninstall('new'), throwsStateError);
      provider.uninstallGate!.complete();
      await failed;
      expect(ssh.leases, isEmpty);
      provider.failUninstall = false;
      await manager.uninstall('new');
    },
  );

  test('uninstall invalidates an in-flight preflight cache result', () async {
    ssh.online('target');
    provider.preflightGate = Completer<void>();
    final pending = manager.preflight('target');
    await manager.uninstall('target');
    provider.preflightGate!.complete();
    await pending;
    await manager.preflight('target');
    expect(provider.probes, 2);
  });

  test(
    'uninstall route accepts no body and returns Result void or failure',
    () async {
      ssh.online('target');
      final router = Router();
      registerCodeServerRoutes(
        router,
        CodeServerController(
          manager: manager,
          packages: IdePackageStore(tempDir),
          sshService: ssh,
        ),
      );
      final response = await router(
        Request(
          'POST',
          Uri.parse(
            'http://localhost/api/code-server/targets/target/uninstall',
          ),
        ),
      );
      expect(response.statusCode, 200);
      expect(jsonDecode(await response.readAsString()), {
        'code': 200,
        'message': 'Success',
        'data': null,
      });
      provider.failUninstall = true;
      final failure = await router(
        Request(
          'POST',
          Uri.parse(
            'http://localhost/api/code-server/targets/target/uninstall',
          ),
        ),
      );
      final body = jsonDecode(await failure.readAsString()) as Map;
      expect(body['code'], 500);
      expect(body['data'], isNull);
    },
  );
}

class _FakeProvider implements RemoteIdeProvider {
  final List<String> starts = [];
  final List<String> uninstalls = [];
  Completer<void>? uninstallGate;
  Completer<void>? preflightGate;
  bool failStop = false;
  bool failUninstall = false;
  int probes = 0;

  @override
  Future<void> uninstall(String connectionId) async {
    uninstalls.add(connectionId);
    await uninstallGate?.future;
    if (failUninstall) throw StateError('remove failed');
  }

  final List<({String connectionId, int pid})> stops = [];

  @override
  Future<IdePreflight> preflight(
    String connectionId, {
    String? expectedVersion,
  }) async {
    probes++;
    await preflightGate?.future;
    return const IdePreflight(
      arch: 'amd64',
      libc: 'glibc 2.39',
      diskFreeBytes: 1 << 40,
      installedVersion: '4.143.1',
      issues: [],
    );
  }

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
    if (failStop) throw StateError('stop failed');
  }
}

class _FakeSshService extends SshService {
  _FakeSshService(this.upstreamPort);

  final int upstreamPort;
  final Set<String> _connected = {};
  final Set<String> leases = {};
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
  void attachLease(String connectionId, String leaseId) {
    leases.add('$connectionId:$leaseId');
  }

  @override
  void detachLease(String connectionId, String leaseId) {
    leases.remove('$connectionId:$leaseId');
  }

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
  Future<void> flush() => _socket.flush();

  @override
  Future<void> close() async => _socket.close();

  @override
  void destroy() => _socket.destroy();
}
