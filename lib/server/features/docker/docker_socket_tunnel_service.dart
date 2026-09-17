import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:logging/logging.dart';

import 'package:host_deck/server/core/ssh/ssh_connection_handle.dart';

abstract interface class DockerSocketTunnelChannel {
  Stream<Uint8List> get stream;
  StreamSink<List<int>> get sink;
  Future<void> get done;
  Future<void> close();
  void destroy();
}

typedef DockerSocketChannelFactory =
    Future<DockerSocketTunnelChannel> Function(SshConnectionHandle connection);
typedef DockerSshDisconnectFutureProvider =
    Future<void> Function(SshConnectionHandle connection);

class DockerSocketTunnelService {
  final String socketPath;
  final DockerSocketChannelFactory? _channelFactory;
  final DockerSshDisconnectFutureProvider _disconnectFutureProvider;
  final _log = Logger('DockerSocketTunnelService');
  final Map<String, Future<_DockerSocketTunnel>> _tunnels = {};

  DockerSocketTunnelService({
    this.socketPath = '/var/run/docker.sock',
    DockerSocketChannelFactory? channelFactory,
    DockerSshDisconnectFutureProvider? disconnectFutureProvider,
  }) : _channelFactory = channelFactory,
       _disconnectFutureProvider =
           disconnectFutureProvider ?? ((connection) => connection.client.done);

  Future<Uri> endpoint(SshConnectionHandle connection) async {
    final connectionId = connection.connectionId;
    final existing = _tunnels[connectionId];
    if (existing != null) {
      return (await existing).endpoint;
    }

    final future = _start(connection);
    _tunnels[connectionId] = future;
    try {
      return (await future).endpoint;
    } catch (_) {
      if (identical(_tunnels[connectionId], future)) {
        _tunnels.remove(connectionId);
      }
      rethrow;
    }
  }

  Future<List<DockerSocketTunnelSnapshot>> listActiveListeners() async {
    final entries = _tunnels.entries.toList(growable: false);
    final snapshots = <DockerSocketTunnelSnapshot>[];
    for (final entry in entries) {
      try {
        final tunnel = await entry.value;
        snapshots.add(
          DockerSocketTunnelSnapshot(
            connectionId: entry.key,
            host: tunnel.endpoint.host,
            port: tunnel.endpoint.port,
          ),
        );
      } catch (_) {
        // Failed tunnel startups are removed by endpoint().
      }
    }
    return snapshots;
  }

  Future<void> stop(String connectionId) async {
    final future = _tunnels.remove(connectionId);
    if (future == null) {
      return;
    }
    try {
      final tunnel = await future;
      await tunnel.close();
      _log.info(
        'Destroyed Docker SSH port forward for connection $connectionId '
        'at ${tunnel.endpoint}.',
      );
    } catch (_) {
      // A failed startup has no live listener left to clean up.
    }
  }

  Future<void> stopAll() async {
    final connectionIds = _tunnels.keys.toList(growable: false);
    await Future.wait(connectionIds.map(stop));
  }

  Future<_DockerSocketTunnel> _start(SshConnectionHandle connection) async {
    final listener = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    late final _DockerSocketTunnel tunnel;
    tunnel = _DockerSocketTunnel(listener, () => _openChannel(connection));
    tunnel.start();
    _log.info(
      'Created Docker SSH port forward for connection ${connection.connectionId} '
      'at ${tunnel.endpoint} to $socketPath.',
    );

    unawaited(
      _disconnectFutureProvider(connection).then(
        (_) => stop(connection.connectionId),
        onError: (_) => stop(connection.connectionId),
      ),
    );
    return tunnel;
  }

  Future<DockerSocketTunnelChannel> _openChannel(
    SshConnectionHandle connection,
  ) async {
    final factory = _channelFactory;
    if (factory != null) {
      return factory(connection);
    }
    final channel = await connection.client.forwardLocalUnix(socketPath);
    return _SshDockerSocketTunnelChannel(channel);
  }
}

class DockerSocketTunnelSnapshot {
  final String connectionId;
  final String host;
  final int port;

  const DockerSocketTunnelSnapshot({
    required this.connectionId,
    required this.host,
    required this.port,
  });
}

class _DockerSocketTunnel {
  final ServerSocket listener;
  final Future<DockerSocketTunnelChannel> Function() openChannel;
  final Set<_ActiveForward> _active = {};
  StreamSubscription<Socket>? _listenerSubscription;
  bool _closed = false;

  _DockerSocketTunnel(this.listener, this.openChannel);

  Uri get endpoint => Uri(
    scheme: 'http',
    host: InternetAddress.loopbackIPv4.address,
    port: listener.port,
  );

  void start() {
    _listenerSubscription = listener.listen(_accept);
  }

  Future<void> _accept(Socket socket) async {
    if (_closed) {
      socket.destroy();
      return;
    }

    DockerSocketTunnelChannel channel;
    try {
      channel = await openChannel();
    } catch (_) {
      socket.destroy();
      return;
    }

    if (_closed) {
      socket.destroy();
      channel.destroy();
      return;
    }

    final forward = _ActiveForward(socket, channel);
    _active.add(forward);
    unawaited(channel.stream.cast<List<int>>().pipe(socket).catchError((_) {}));
    unawaited(socket.cast<List<int>>().pipe(channel.sink).catchError((_) {}));
    unawaited(
      Future.any<void>([
        socket.done.catchError((_) {}),
        channel.done.catchError((_) {}),
      ]).whenComplete(() {
        _active.remove(forward);
        forward.close();
      }),
    );
  }

  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await _listenerSubscription?.cancel();
    await listener.close();
    final active = _active.toList(growable: false);
    _active.clear();
    await Future.wait(active.map((forward) => forward.close()));
  }
}

class _ActiveForward {
  final Socket socket;
  final DockerSocketTunnelChannel channel;
  bool _closed = false;

  _ActiveForward(this.socket, this.channel);

  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    socket.destroy();
    channel.destroy();
  }
}

class _SshDockerSocketTunnelChannel implements DockerSocketTunnelChannel {
  final SSHForwardChannel _channel;

  _SshDockerSocketTunnelChannel(this._channel);

  @override
  Stream<Uint8List> get stream => _channel.stream;

  @override
  StreamSink<List<int>> get sink => _channel.sink;

  @override
  Future<void> get done => _channel.done;

  @override
  Future<void> close() => _channel.close();

  @override
  void destroy() => _channel.destroy();
}
