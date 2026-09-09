import 'package:host_deck/server/features/docker/docker_socket_tunnel_service.dart';
import 'package:host_deck/server/features/port_forwards/port_forward_service.dart';
import 'package:host_deck/server/features/port_forwards/secure_browser_tunnel_service.dart';

class BackendPortsService {
  final String Function() _serverHost;
  final int Function() _serverPort;
  final PortForwardService _portForwardService;
  final SecureBrowserTunnelService _secureBrowserTunnelService;
  final DockerSocketTunnelService _dockerSocketTunnelService;

  BackendPortsService({
    required String Function() serverHost,
    required int Function() serverPort,
    required PortForwardService portForwardService,
    required SecureBrowserTunnelService secureBrowserTunnelService,
    required DockerSocketTunnelService dockerSocketTunnelService,
  }) : _serverHost = serverHost,
       _serverPort = serverPort,
       _portForwardService = portForwardService,
       _secureBrowserTunnelService = secureBrowserTunnelService,
       _dockerSocketTunnelService = dockerSocketTunnelService;

  Future<List<Map<String, dynamic>>> list() async {
    final items = <Map<String, dynamic>>[
      {
        'id': 'server-main',
        'type': 'server',
        'name': 'HostDeck 主服务',
        'host': _serverHost(),
        'port': _serverPort(),
        'purpose': 'Web 页面、HTTP API、WebSocket 与事件流',
        'status': 'running',
      },
    ];

    for (final listener in _portForwardService.listActiveListeners()) {
      items.add({
        'id': 'port-forward-${listener.ruleId}',
        'type': 'port-forward',
        'name': listener.name,
        'host': listener.host,
        'port': listener.port,
        'purpose': '通过 SSH 转发本地 TCP 连接',
        'status': listener.error == null ? 'running' : 'error',
        'target': '${listener.remoteHost}:${listener.remotePort}',
        'connectionId': listener.connectionId,
        'activeConnections': listener.activeConnections,
        'startedAt': listener.startedAt,
        'error': ?listener.error,
      });
    }

    for (final tunnel in _secureBrowserTunnelService.list()) {
      items.add({
        'id': 'secure-browser-${tunnel.id}',
        'type': 'secure-browser',
        'name': '安全浏览器代理',
        'host': tunnel.bindHost,
        'port': tunnel.bindPort,
        'purpose': '通过 SSH 提供安全浏览器 SOCKS 代理',
        'status': 'running',
        'connectionId': tunnel.connectionId,
        'startedAt': tunnel.startedAt,
      });
    }

    for (final tunnel
        in await _dockerSocketTunnelService.listActiveListeners()) {
      items.add({
        'id': 'docker-${tunnel.connectionId}',
        'type': 'docker',
        'name': 'Docker Socket 隧道',
        'host': tunnel.host,
        'port': tunnel.port,
        'purpose': '经 SSH 访问远程 Docker Engine',
        'status': 'running',
        'target': _dockerSocketTunnelService.socketPath,
        'connectionId': tunnel.connectionId,
      });
    }

    return items;
  }
}
