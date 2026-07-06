import 'dart:async';
import 'dart:io';

import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:logging/logging.dart';

import 'package:host_deck/server/app/server_container.dart';
import 'package:host_deck/server/app/server_handlers.dart';

class ServerService {
  final _log = Logger('ServerService');
  HttpServer? _server;
  int port;
  String host;
  String? webDir;
  String? dataDir;
  ServerContainer? _container;

  bool get isRunning => _server != null;

  ServerService({
    this.port = 8080,
    this.host = '0.0.0.0',
    this.webDir,
    this.dataDir,
  });

  Future<void> start() async {
    if (isRunning) return;

    final staticPath = webDir?.trim() ?? '';
    if (staticPath.isNotEmpty) {
      final staticDir = Directory(staticPath);
      if (!staticDir.existsSync()) {
        _log.warning('Static web directory does not exist: $staticPath');
      } else {
        _log.info('Serving static web assets from: $staticPath');
      }
    }

    _container = await ServerContainer.create(dataDir: dataDir, log: _log);
    final handler = await buildServerHandler(
      apiRoutes: _container!.apiRoutes,
      staticPath: staticPath,
      log: _log,
    );

    final bindAddress = _parseBindAddress(host);
    _server = await shelf_io.serve(handler, bindAddress, port);

    final startMsg = 'Server running on port ${_server?.port}';
    _log.info(startMsg);
  }

  Future<void> stop() async {
    if (_server != null) {
      await _server?.close(force: true);
      _server = null;
    }
    await _container?.portForwardService.stopAll();
    _container?.databaseService.close();
    _container = null;
  }

  Object _parseBindAddress(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty || normalized == '0.0.0.0') {
      return InternetAddress.anyIPv4;
    }
    if (normalized == '::' || normalized == '[::]') {
      return InternetAddress.anyIPv6;
    }

    return InternetAddress.tryParse(normalized) ?? normalized;
  }
}
