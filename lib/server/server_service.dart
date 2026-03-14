import 'dart:async';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import 'repositories/ssh_repository.dart';
import 'services/ssh_service.dart';
import 'services/monitor_service.dart';
import 'services/file_service.dart';
import 'controllers/auth_controller.dart';
import 'controllers/system_controller.dart';
import 'controllers/file_controller.dart';
import 'controllers/terminal_controller.dart';
import 'routes/api_routes.dart';

class ServerService {
  HttpServer? _server;
  final int port;

  bool get isRunning => _server != null;

  ServerService({this.port = 8080});

  Future<void> start({void Function(String)? onLog}) async {
    if (isRunning) return;

    // 1. Initialize dependencies
    final sshRepository = SshRepository();
    final sshService = SshService(); // Manages connections
    final monitorService = MonitorService(sshRepository);
    final fileService = FileService(sshRepository);

    // 2. Initialize Controllers
    final authController = AuthController(sshService);
    final systemController = SystemController(sshService, monitorService);
    final fileController = FileController(sshService, fileService);
    final terminalController = TerminalController(sshService);

    // 3. Initialize Routes
    final apiRoutes = ApiRoutes(
      authController: authController,
      systemController: systemController,
      fileController: fileController,
      terminalController: terminalController,
    );

    // 4. Setup Server
    final handler = Pipeline()
        .addMiddleware(logRequests(logger: (message, isError) {
          if (onLog != null) {
            onLog(message);
          } else {
            print(message);
          }
        }))
        .addHandler(apiRoutes.router.call);

    _server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
    
    final startMsg = 'Server running on port ${_server?.port}';
    if (onLog != null) {
      onLog(startMsg);
    } else {
      print(startMsg);
    }
  }

  Future<void> stop() async {
    if (_server != null) {
      await _server?.close(force: true);
      _server = null;
    }
  }
}
