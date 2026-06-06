import 'dart:async';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:logging/logging.dart';

import '../models/port_forward_rule.dart';
import 'ssh_service.dart';

class PortForwardService {
  final SshService _sshService;
  final _log = Logger('PortForwardService');
  final Map<int, _ActivePortForward> _activeForwards = {};

  PortForwardService(this._sshService) {
    _sshService.addDisconnectListener(stopByConnection);
  }

  Map<String, dynamic> statusFor(int ruleId) {
    final active = _activeForwards[ruleId];
    if (active == null) {
      return {'status': 'stopped', 'error': null, 'connectionId': null};
    }

    return {
      'status': active.error == null ? 'running' : 'error',
      'error': active.error,
      'connectionId': active.connectionId,
      'startedAt': active.startedAt,
      'activeConnections': active.activeConnections,
    };
  }

  Future<void> start(String connectionId, PortForwardRule rule) async {
    final id = rule.id;
    if (id == null) {
      throw ArgumentError('Port forward rule ID is required.');
    }

    _validateRule(rule);
    await stop(id);

    final client = _sshService.getClient(connectionId);
    if (client == null || client.isClosed) {
      throw Exception('Connection not found: $connectionId');
    }

    late final ServerSocket server;
    try {
      server = await ServerSocket.bind(rule.bindHost, rule.localPort);
    } catch (error) {
      throw Exception('本地端口监听失败：$error');
    }

    final active = _ActivePortForward(
      connectionId: connectionId,
      ruleId: id,
      server: server,
      startedAt: DateTime.now().millisecondsSinceEpoch,
    );
    _activeForwards[id] = active;

    active.subscription = server.listen(
      (socket) => _handleSocket(client, rule, active, socket),
      onError: (Object error) {
        active.error = error.toString();
        _log.warning('Port forward listener error for rule $id: $error');
      },
      onDone: () {
        if (_activeForwards[id] == active) {
          _activeForwards.remove(id);
        }
      },
      cancelOnError: false,
    );
  }

  Future<void> stop(int ruleId) async {
    final active = _activeForwards.remove(ruleId);
    if (active == null) {
      return;
    }

    await active.close();
  }

  Future<void> stopByConnection(String connectionId) async {
    final ruleIds = _activeForwards.entries
        .where((entry) => entry.value.connectionId == connectionId)
        .map((entry) => entry.key)
        .toList();

    for (final ruleId in ruleIds) {
      await stop(ruleId);
    }
  }

  Future<void> stopAll() async {
    final ruleIds = _activeForwards.keys.toList();
    for (final ruleId in ruleIds) {
      await stop(ruleId);
    }
  }

  Future<void> _handleSocket(
    SSHClient client,
    PortForwardRule rule,
    _ActivePortForward active,
    Socket socket,
  ) async {
    SSHForwardChannel? channel;
    StreamSubscription<List<int>>? socketSub;
    StreamSubscription<List<int>>? channelSub;

    active.activeConnections++;

    Future<void> closeBoth() async {
      await socketSub?.cancel();
      await channelSub?.cancel();
      socket.destroy();
      channel?.destroy();
    }

    try {
      channel = await client.forwardLocal(
        rule.remoteHost,
        rule.remotePort,
        localHost: rule.bindHost,
        localPort: rule.localPort,
      );

      socketSub = socket.listen(
        channel.sink.add,
        onError: (_) => closeBoth(),
        onDone: () => channel?.sink.close(),
        cancelOnError: true,
      );
      channelSub = channel.stream.listen(
        socket.add,
        onError: (_) => closeBoth(),
        onDone: () => socket.destroy(),
        cancelOnError: true,
      );

      await Future.wait([socket.done, channel.done]);
    } catch (error) {
      active.error = error.toString();
      _log.warning('Port forward connection error for rule ${rule.id}: $error');
      await closeBoth();
    } finally {
      active.activeConnections--;
    }
  }

  void _validateRule(PortForwardRule rule) {
    if (rule.name.trim().isEmpty) {
      throw ArgumentError('名称不能为空。');
    }
    if (rule.bindHost.trim().isEmpty) {
      throw ArgumentError('本地绑定地址不能为空。');
    }
    if (rule.remoteHost.trim().isEmpty) {
      throw ArgumentError('远端主机不能为空。');
    }
    if (!_isValidPort(rule.localPort) || !_isValidPort(rule.remotePort)) {
      throw ArgumentError('端口范围必须是 1-65535。');
    }
  }

  bool _isValidPort(int port) => port > 0 && port <= 65535;
}

class _ActivePortForward {
  final String connectionId;
  final int ruleId;
  final ServerSocket server;
  final int startedAt;
  StreamSubscription<Socket>? subscription;
  String? error;
  int activeConnections = 0;

  _ActivePortForward({
    required this.connectionId,
    required this.ruleId,
    required this.server,
    required this.startedAt,
  });

  Future<void> close() async {
    await subscription?.cancel();
    await server.close();
  }
}
