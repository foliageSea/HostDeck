import 'dart:math';

import 'package:dartssh2/dartssh2.dart';
import 'package:logging/logging.dart';

import 'package:host_deck/server/core/ssh/ssh_service.dart';
import 'package:host_deck/server/features/port_forwards/secure_browser_tunnel.dart';

typedef DynamicForwardFactory =
    Future<SSHDynamicForward> Function(
      SSHClient client,
      SSHDynamicConnectionFilter filter,
    );

class SecureBrowserTunnelService {
  final SshService _sshService;
  final DynamicForwardFactory _forwardFactory;
  final _log = Logger('SecureBrowserTunnelService');
  final _random = Random.secure();
  final Map<String, _ActiveSecureBrowserTunnel> _tunnels = {};
  final Map<String, Future<SecureBrowserTunnel>> _pendingCreates = {};
  final Set<String> _disconnectedConnections = {};

  SecureBrowserTunnelService(
    this._sshService, {
    DynamicForwardFactory? forwardFactory,
  }) : _forwardFactory = forwardFactory ?? _createDynamicForward {
    _sshService.addDisconnectListener(stopByConnection);
  }

  List<SecureBrowserTunnel> list() {
    final tunnels = _tunnels.values.map((active) => active.tunnel).toList();
    tunnels.sort((left, right) => right.startedAt.compareTo(left.startedAt));
    return tunnels;
  }

  Future<SecureBrowserTunnel> create({required String connectionId}) {
    if (_disconnectedConnections.contains(connectionId)) {
      return Future.error(StateError('SSH 连接不存在或已断开。'));
    }
    for (final active in _tunnels.values) {
      if (active.tunnel.connectionId == connectionId) {
        return Future.value(active.tunnel);
      }
    }

    final pending = _pendingCreates[connectionId];
    if (pending != null) return pending;

    final creation = _create(connectionId);
    _pendingCreates[connectionId] = creation;
    return creation.whenComplete(() {
      if (_pendingCreates[connectionId] == creation) {
        _pendingCreates.remove(connectionId);
      }
    });
  }

  Future<SecureBrowserTunnel> _create(String connectionId) async {
    final client = _sshService.getClient(connectionId);
    if (client == null || client.isClosed) {
      throw StateError('SSH 连接不存在或已断开。');
    }

    final forward = await _forwardFactory(client, _allowTarget);
    if (_disconnectedConnections.contains(connectionId) ||
        _sshService.getClient(connectionId) != client ||
        client.isClosed) {
      await forward.close();
      throw StateError('SSH 连接不存在或已断开。');
    }
    final tunnel = SecureBrowserTunnel(
      id: _generateId(),
      connectionId: connectionId,
      bindHost: forward.host,
      bindPort: forward.port,
      startedAt: DateTime.now().millisecondsSinceEpoch,
    );
    _tunnels[tunnel.id] = _ActiveSecureBrowserTunnel(tunnel, forward);
    _log.info(
      'Created secure browser tunnel ${tunnel.id} for SSH connection $connectionId.',
    );
    return tunnel;
  }

  Future<void> stop(String id) async {
    final active = _tunnels.remove(id);
    if (active == null) {
      return;
    }
    await active.forward.close();
    _log.info('Stopped secure browser tunnel $id.');
  }

  Future<void> stopByConnection(String connectionId) async {
    _disconnectedConnections.add(connectionId);
    final ids = _tunnels.values
        .where((active) => active.tunnel.connectionId == connectionId)
        .map((active) => active.tunnel.id)
        .toList();
    for (final id in ids) {
      await stop(id);
    }
  }

  Future<void> stopAll() async {
    for (final id in _tunnels.keys.toList()) {
      await stop(id);
    }
  }

  bool _allowTarget(String host, int port) {
    if (host.trim().isEmpty || port < 1 || port > 65535) return false;

    final normalizedHost = host
        .toLowerCase()
        .replaceAll(RegExp(r'^\[|\]$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
    const blockedHosts = {
      '169.254.169.254',
      '169.254.170.2',
      '100.100.100.200',
      'fd00:ec2::254',
      'metadata.google.internal',
      'metadata.goog',
    };
    return !blockedHosts.contains(normalizedHost);
  }

  String _generateId() {
    final values = List<int>.generate(16, (_) => _random.nextInt(256));
    return values
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  static Future<SSHDynamicForward> _createDynamicForward(
    SSHClient client,
    SSHDynamicConnectionFilter filter,
  ) {
    return client.forwardDynamic(
      bindHost: '127.0.0.1',
      options: const SSHDynamicForwardOptions(maxConnections: 128),
      filter: filter,
    );
  }
}

class _ActiveSecureBrowserTunnel {
  final SecureBrowserTunnel tunnel;
  final SSHDynamicForward forward;

  const _ActiveSecureBrowserTunnel(this.tunnel, this.forward);
}
