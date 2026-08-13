import 'dart:async';
import 'dart:io';

import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:logging/logging.dart';

import 'package:host_deck/server/app/server_container.dart';
import 'package:host_deck/server/app/server_handlers.dart';
import 'package:host_deck/server/features/logs/server_log_service.dart';
import 'package:host_deck/utils/hostdeck_discovery.dart';

class ServerService {
  final _log = Logger('ServerService');
  HttpServer? _server;
  int port;
  String host;
  String? webDir;
  String? dataDir;
  String? logDir;
  Future<void> Function()? flushLogs;
  String? adminPassword;
  String? apiToken;
  bool secureCookies;
  final ServerLogService logService;
  final bool _ownsLogService;
  ServerContainer? _container;
  bool _disposed = false;

  bool get isRunning => _server != null;

  ServerService({
    this.port = 8080,
    this.host = '127.0.0.1',
    this.webDir,
    this.dataDir,
    this.logDir,
    this.flushLogs,
    this.adminPassword,
    this.apiToken,
    this.secureCookies = false,
    ServerLogService? logService,
  }) : logService = logService ?? ServerLogService(),
       _ownsLogService = logService == null;

  Future<void> start() async {
    if (_disposed) {
      throw StateError('ServerService has been disposed.');
    }
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

    if (!_isLoopbackHost(host) && !_hasAccessCredential) {
      throw StateError(
        'Non-loopback binding requires HOSTDECK_ACCESS_PASSWORD or HOSTDECK_API_TOKEN.',
      );
    }

    _container = await ServerContainer.create(
      dataDir: dataDir,
      logDir: logDir,
      flushLogs: flushLogs,
      log: _log,
      adminPassword: adminPassword,
      apiToken: apiToken,
      secureCookies: secureCookies,
      logService: logService,
    );
    final handler = await buildServerHandler(
      apiRoutes: _container!.apiRoutes,
      staticPath: staticPath,
      log: _log,
      accessService: _container!.accessService,
      operationLogService: _container!.operationLogService,
      portForwardRepository: _container!.portForwardRepository,
      serverRepository: _container!.serverRepository,
    );

    final bindAddress = _parseBindAddress(host);
    _server = await shelf_io.serve(handler, bindAddress, port);
    port = _server!.port;
    try {
      await HostDeckDiscovery.writeInstance(
        baseUrl: HostDeckDiscovery.localBaseUrl(port),
        host: _discoveryHost(host),
        port: port,
        dataDir: dataDir,
      );
    } catch (e) {
      _log.warning('Failed to write HostDeck discovery file: $e');
    }

    final startMsg = 'Server running on port ${_server?.port}';
    _log.info(startMsg);
  }

  Future<void> stop() async {
    if (_server != null) {
      await _server?.close(force: true);
      _server = null;
      try {
        await HostDeckDiscovery.deleteInstance();
      } catch (e) {
        _log.warning('Failed to delete HostDeck discovery file: $e');
      }
    }
    await _container?.dispose();
    _container = null;
  }

  Future<void> dispose() async {
    if (_disposed) return;
    await stop();
    if (_ownsLogService) {
      await logService.dispose();
    }
    _disposed = true;
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

  String _discoveryHost(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty || normalized == '0.0.0.0' || normalized == '::') {
      return '127.0.0.1';
    }
    if (normalized == '[::]') {
      return '127.0.0.1';
    }
    return normalized;
  }

  bool get _hasAccessCredential =>
      (adminPassword?.trim().isNotEmpty ?? false) ||
      (apiToken?.trim().isNotEmpty ?? false);

  bool _isLoopbackHost(String value) {
    final normalized = value.trim().toLowerCase();
    return normalized == '127.0.0.1' ||
        normalized == '::1' ||
        normalized == '[::1]' ||
        normalized == 'localhost';
  }
}
