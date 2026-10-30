import 'dart:async';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:logging/logging.dart';

import 'package:host_deck/server/core/ssh/ssh_service.dart';

/// 把本地 loopback 端口桥接到远端 127.0.0.1 上的指定端口。
///
/// HTTP 与 WebSocket 共用同一条 TCP 隧道：每个本地连接对应一条 SSH
/// direct-tcpip 通道（SSHClient.forwardLocal）。监听地址固定为
/// 127.0.0.1:0，由系统分配随机端口，避免把 code-server 的
/// --auth none 端口暴露到局域网。
class LoopbackSshBridge {
  /// 单个 bridge 允许的最大并发连接数。
  static const int maxConnections = 64;

  final ServerSocket _server;
  final SSHClient _client;
  final SshService _sshService;
  final String _connectionId;
  final int _remotePort;
  final Logger _log = Logger('LoopbackSshBridge');
  final Set<_ActiveBridgeConnection> _connections = {};
  StreamSubscription<Socket>? _subscription;
  bool _closed = false;

  LoopbackSshBridge._({
    required ServerSocket server,
    required SSHClient client,
    required SshService sshService,
    required String connectionId,
    required int remotePort,
  }) : _server = server,
       _client = client,
       _sshService = sshService,
       _connectionId = connectionId,
       _remotePort = remotePort;

  /// 在 127.0.0.1:0 上监听，并把每条本地连接转发到远端 [remotePort]。
  static Future<LoopbackSshBridge> start({
    required SshService sshService,
    required String connectionId,
    required int remotePort,
  }) async {
    if (remotePort < 1 || remotePort > 65535) {
      throw ArgumentError.value(remotePort, 'remotePort', '端口范围必须是 1-65535');
    }

    final client = sshService.getClient(connectionId);
    if (client == null || client.isClosed) {
      throw StateError('SSH 连接不存在或已断开：$connectionId');
    }

    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final bridge = LoopbackSshBridge._(
      server: server,
      client: client,
      sshService: sshService,
      connectionId: connectionId,
      remotePort: remotePort,
    );
    bridge._start();
    sshService.touch(connectionId);
    bridge._watchClient();
    return bridge;
  }

  /// 本地监听端口，代理通过它访问远端 code-server。
  int get localPort => _server.port;

  String get localHost => _server.address.address;

  int get remotePort => _remotePort;

  int get activeConnections => _connections.length;

  bool get isClosed => _closed;

  void _start() {
    _subscription = _server.listen(
      _accept,
      onError: (Object error) {
        _log.warning('本地 bridge 监听失败：$error');
      },
      cancelOnError: false,
    );
  }

  /// SSH 连接断开时自动关闭监听与所有转发通道。
  void _watchClient() {
    unawaited(
      _client.done
          .whenComplete(() {
            unawaited(close());
          })
          .catchError((Object error) {
            _log.fine('bridge 等待 SSH 连接结束时出错：$error');
          }),
    );
  }

  Future<void> _accept(Socket socket) async {
    if (_closed) {
      socket.destroy();
      return;
    }

    if (_connections.length >= maxConnections) {
      _log.warning('bridge 并发连接达到上限 $maxConnections，拒绝新连接');
      socket.destroy();
      return;
    }

    final connection = _ActiveBridgeConnection(socket);
    _connections.add(connection);

    try {
      final channel = await _client.forwardLocal('127.0.0.1', _remotePort);
      if (_closed) {
        channel.destroy();
        connection.destroy();
        _connections.remove(connection);
        return;
      }

      connection.attach(channel);
      _sshService.touch(_connectionId);

      unawaited(
        channel.stream.cast<List<int>>().pipe(socket).catchError((
          Object error,
        ) {
          _log.fine('bridge 远端到本地方向中断：$error');
        }),
      );
      unawaited(
        socket.cast<List<int>>().pipe(channel.sink).catchError((Object error) {
          _log.fine('bridge 本地到远端方向中断：$error');
        }),
      );
      // 本地对端（HostDeck 代理）先关闭时，写入失败会在 socket.done 上抛出
      // Broken pipe；每个 done future 都要有处理器，避免未捕获的异步错误。
      final socketDone = socket.done.then<void>((_) {}, onError: (Object _) {});
      final channelDone = channel.done.then<void>(
        (_) {},
        onError: (Object _) {},
      );
      unawaited(
        Future.any<void>([socketDone, channelDone]).whenComplete(() {
          connection.destroy();
          _connections.remove(connection);
        }),
      );
    } catch (error) {
      _log.warning('bridge 打开 SSH 转发通道失败：$error');
      connection.destroy();
      _connections.remove(connection);
    }
  }

  /// 关闭监听并断开所有活跃连接；可重复调用。
  Future<void> close() async {
    if (_closed) {
      return;
    }

    _closed = true;
    await _subscription?.cancel();
    _subscription = null;
    await _server.close();

    final active = _connections.toList(growable: false);
    _connections.clear();
    for (final connection in active) {
      connection.destroy();
    }
    _log.fine('bridge 已关闭（connection=$_connectionId, remotePort=$_remotePort）');
  }
}

class _ActiveBridgeConnection {
  final Socket socket;
  SSHForwardChannel? _channel;
  bool _destroyed = false;

  _ActiveBridgeConnection(this.socket);

  void attach(SSHForwardChannel channel) {
    _channel = channel;
  }

  void destroy() {
    if (_destroyed) {
      return;
    }

    _destroyed = true;
    socket.destroy();
    _channel?.destroy();
  }
}
