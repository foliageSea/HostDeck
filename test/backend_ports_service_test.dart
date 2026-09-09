import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:host_deck/server/core/ssh/ssh_service.dart';
import 'package:host_deck/server/features/docker/docker_socket_tunnel_service.dart';
import 'package:host_deck/server/features/port_forwards/port_forward_rule.dart';
import 'package:host_deck/server/features/port_forwards/port_forward_service.dart';
import 'package:host_deck/server/features/port_forwards/secure_browser_tunnel_service.dart';
import 'package:host_deck/server/features/settings/backend_ports_service.dart';
import 'package:host_deck/server/features/settings/log_export_service.dart';
import 'package:host_deck/server/features/settings/settings_controller.dart';
import 'package:shelf/shelf.dart';

void main() {
  test(
    'returns all active backend listeners without creating Docker tunnels',
    () async {
      final sshService = _FakeSshService();
      final portForwardService = PortForwardService(sshService);
      final secureBrowserService = SecureBrowserTunnelService(
        sshService,
        forwardFactory: (_, _) async => _FakeDynamicForward(),
      );
      final dockerService = DockerSocketTunnelService();
      addTearDown(portForwardService.stopAll);
      addTearDown(secureBrowserService.stopAll);
      addTearDown(dockerService.stopAll);

      final localPort = await _availablePort();
      await portForwardService.start(
        'connection-1',
        PortForwardRule(
          id: 7,
          name: '数据库转发',
          enabled: true,
          bindHost: '127.0.0.1',
          localPort: localPort,
          remoteHost: 'db.internal',
          remotePort: 5432,
        ),
      );
      await secureBrowserService.create(connectionId: 'connection-1');

      final service = BackendPortsService(
        serverHost: () => '127.0.0.1',
        serverPort: () => 18080,
        portForwardService: portForwardService,
        secureBrowserTunnelService: secureBrowserService,
        dockerSocketTunnelService: dockerService,
      );
      final controller = SettingsController(
        LogExportService(logDirectory: null),
        backendPortsService: service,
      );

      final response = await controller.getBackendPorts(
        Request('GET', Uri.parse('http://localhost/api/settings/ports')),
      );
      final payload = jsonDecode(await response.readAsString());
      final items = (payload['data']['items'] as List)
          .cast<Map<String, dynamic>>();

      expect(payload['code'], HttpStatus.ok);
      expect(items, hasLength(3));
      expect(items[0], containsPair('port', 18080));
      expect(
        items,
        contains(
          allOf(
            containsPair('type', 'port-forward'),
            containsPair('port', localPort),
            containsPair('target', 'db.internal:5432'),
          ),
        ),
      );
      expect(
        items,
        contains(
          allOf(
            containsPair('type', 'secure-browser'),
            containsPair('port', 49152),
          ),
        ),
      );
      expect(await dockerService.listActiveListeners(), isEmpty);
    },
  );
}

Future<int> _availablePort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

class _FakeSshService extends SshService {
  final SSHClient _client = _FakeSshClient();

  @override
  SSHClient? getClient(String connectionId) => _client;

  @override
  void addDisconnectListener(
    FutureOr<void> Function(String connectionId) listener,
  ) {}
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
