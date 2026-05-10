import 'dart:async';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_static/shelf_static.dart';
import 'package:logging/logging.dart';

import 'repositories/ssh_repository.dart';
import 'repositories/server_repository.dart';
import 'services/ssh_service.dart';
import 'services/monitor_history_service.dart';
import 'services/monitor_service.dart';
import 'services/file_service.dart';
import 'services/process_service.dart';
import 'services/docker_service.dart';
import 'services/database_service.dart';
import 'controllers/auth_controller.dart';
import 'controllers/system_controller.dart';
import 'controllers/file_controller.dart';
import 'controllers/terminal_controller.dart';
import 'controllers/server_controller.dart';
import 'controllers/docker_controller.dart';
import 'controllers/process_controller.dart';
import 'controllers/runtime_controller.dart';
import 'routes/api_routes.dart';

class ServerService {
  final _log = Logger('ServerService');
  HttpServer? _server;
  int port;
  String host;
  String? webDir;
  String? dataDir;
  DatabaseService? _dbService;

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

    // 1. Initialize dependencies
    _dbService = DatabaseService(dataDir: dataDir);
    try {
      await _dbService!.init();
      _log.info('Database initialized.');
    } catch (e) {
      _log.severe('Database initialization failed: $e');
    }

    final sshRepository = SshRepository();
    final serverRepository = ServerRepository(_dbService!);
    final sshService = SshService(); // Manages connections
    final monitorHistoryService = MonitorHistoryService();
    final monitorService = MonitorService(sshRepository);
    final fileService = FileService(sshRepository);
    final processService = ProcessService(sshRepository);
    final dockerService = DockerService(sshRepository);

    // 2. Initialize Controllers
    final authController = AuthController(sshService, monitorHistoryService);
    final systemController = SystemController(
      sshService,
      monitorService,
      monitorHistoryService,
    );
    final fileController = FileController(sshService, fileService);
    final processController = ProcessController(sshService, processService);
    final terminalController = TerminalController(sshService);
    final serverController = ServerController(serverRepository);
    final dockerController = DockerController(sshService, dockerService);
    final runtimeController = RuntimeController(sshService);

    // 3. Initialize Routes
    final apiRoutes = ApiRoutes(
      authController: authController,
      systemController: systemController,
      fileController: fileController,
      terminalController: terminalController,
      serverController: serverController,
      dockerController: dockerController,
      processController: processController,
      runtimeController: runtimeController,
    );

    // 4. Setup Static Handler
    Handler? staticHandler;
    if (staticPath.isNotEmpty) {
      staticHandler = createStaticHandler(
        staticPath,
        defaultDocument: 'index.html',
      );
    }

    // SPA Fallback Handler
    Response spaFallback(Request request) {
      if (request.url.path.startsWith('api/')) {
        return Response.notFound('API Route not found');
      }
      if (staticPath.isNotEmpty) {
        final indexFile = File('$staticPath/index.html');
        if (indexFile.existsSync()) {
          return Response.ok(
            indexFile.readAsBytesSync(),
            headers: {'content-type': 'text/html'},
          );
        }
      }
      return Response.notFound('Not found');
    }

    // 5. Setup Cascade
    var cascade = Cascade().add(apiRoutes.router.call);

    if (staticHandler != null) {
      cascade = cascade.add(staticHandler);
    }

    cascade = cascade.add(spaFallback);

    final handler = Pipeline()
        .addMiddleware(
          logRequests(
            logger: (message, isError) {
              if (isError) {
                _log.severe(message);
              } else {
                _log.info(message);
              }
            },
          ),
        )
        .addHandler(cascade.handler);

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
    _dbService?.close();
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
