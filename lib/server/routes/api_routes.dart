import 'package:shelf_router/shelf_router.dart';
import '../controllers/auth_controller.dart';
import '../controllers/system_controller.dart';
import '../controllers/file_controller.dart';
import '../controllers/terminal_controller.dart';
import '../controllers/server_controller.dart';

class ApiRoutes {
  final AuthController authController;
  final SystemController systemController;
  final FileController fileController;
  final TerminalController terminalController;
  final ServerController serverController;

  ApiRoutes({
    required this.authController,
    required this.systemController,
    required this.fileController,
    required this.terminalController,
    required this.serverController,
  });

  Router get router {
    final router = Router();

    // Auth
    router.post('/api/connect', authController.connect);

    // Servers
    router.get('/api/servers', serverController.list);
    router.post('/api/servers', serverController.create);
    router.put('/api/servers/<id>', serverController.update);
    router.delete('/api/servers/<id>', serverController.delete);

    // System
    router.get('/api/status', systemController.status);
    router.get('/api/monitor', systemController.monitor);

    // Files
    router.get('/api/files/list', fileController.listFiles);
    router.post('/api/files/session', fileController.createSession);
    router.get('/api/files/read', fileController.readFile);
    router.post('/api/files/write', fileController.writeFile);
    router.post('/api/files/delete', fileController.deleteFile);
    router.post('/api/files/upload', fileController.uploadFile);
    router.post('/api/files/batch-download', fileController.batchDownload);
    router.post('/api/files/rename', fileController.rename);
    router.post('/api/files/mkdir', fileController.mkdir);
    router.post('/api/files/copy', fileController.copy);

    // Terminal
    router.get('/socket.io', terminalController.handler);
    router.post('/api/terminal/session', terminalController.createSession);
    router.delete('/api/terminal/session', terminalController.closeSession);

    return router;
  }
}
