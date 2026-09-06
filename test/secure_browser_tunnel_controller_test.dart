import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:host_deck/server/core/ssh/ssh_service.dart';
import 'package:host_deck/server/features/port_forwards/chrome_launcher.dart';
import 'package:host_deck/server/features/port_forwards/secure_browser_tunnel_controller.dart';
import 'package:host_deck/server/features/port_forwards/secure_browser_tunnel_service.dart';
import 'package:shelf/shelf.dart';

void main() {
  test('launches Chrome with the server-owned tunnel port', () async {
    final service = SecureBrowserTunnelService(
      _FakeSshService(),
      forwardFactory: (_, _) async => _FakeDynamicForward(),
    );
    addTearDown(service.stopAll);
    final tunnel = await service.create(connectionId: 'connection-1');
    final dataDirectory = await Directory.systemTemp.createTemp(
      'hostdeck-controller-',
    );
    addTearDown(() => dataDirectory.delete(recursive: true));
    late List<String> startedArguments;
    final controller = SecureBrowserTunnelController(
      service,
      chromeLauncher: ChromeLauncher(
        dataDirectory: dataDirectory,
        executablePath: '/custom/chrome',
        executableExists: (_) => true,
        processStarter: (_, arguments) async {
          startedArguments = arguments;
        },
      ),
    );

    final response = await controller.launch(
      Request(
        'POST',
        Uri.parse(
          'http://localhost/api/secure-browser-tunnels/${tunnel.id}/launch',
        ),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'url': 'https://grafana.internal'}),
      ),
      tunnel.id,
    );

    expect(response.statusCode, 200);
    expect(
      startedArguments,
      contains('--proxy-server=socks5://127.0.0.1:49152'),
    );
    expect(startedArguments.last, 'https://grafana.internal');
  });

  test(
    'rejects server-side launch when the CLI capability is disabled',
    () async {
      final service = SecureBrowserTunnelService(_FakeSshService());
      final controller = SecureBrowserTunnelController(service);

      final response = await controller.launch(
        Request(
          'POST',
          Uri.parse(
            'http://localhost/api/secure-browser-tunnels/missing/launch',
          ),
        ),
        'missing',
      );

      expect(response.statusCode, 403);
      expect(await response.readAsString(), contains('未启用'));
    },
  );
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
