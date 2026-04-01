import 'package:shelf_router/shelf_router.dart';
import '../controllers/auth_controller.dart';
import '../controllers/system_controller.dart';
import '../controllers/file_controller.dart';
import '../controllers/terminal_controller.dart';
import '../controllers/server_controller.dart';
import '../controllers/docker_controller.dart';

class ApiRoutes {
  final AuthController authController;
  final SystemController systemController;
  final FileController fileController;
  final TerminalController terminalController;
  final ServerController serverController;
  final DockerController dockerController;

  ApiRoutes({
    required this.authController,
    required this.systemController,
    required this.fileController,
    required this.terminalController,
    required this.serverController,
    required this.dockerController,
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
    router.get('/api/ws/monitor', systemController.wsMonitor);
    router.get('/api/ws/session', systemController.wsSessionStatus);

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

    // Docker
    router.get('/api/docker/check', dockerController.checkDocker);
    router.get('/api/docker/containers', dockerController.listContainers);
    router.post(
      '/api/docker/containers/<id>/shell',
      dockerController.createContainerShellSession,
    );
    router.get('/api/docker/images', dockerController.listImages);
    router.post(
      '/api/docker/containers/<id>/start',
      dockerController.startContainer,
    );
    router.post(
      '/api/docker/containers/<id>/stop',
      dockerController.stopContainer,
    );
    router.post(
      '/api/docker/containers/<id>/restart',
      dockerController.restartContainer,
    );
    router.delete(
      '/api/docker/containers/<id>',
      dockerController.removeContainer,
    );
    router.get(
      '/api/docker/containers/logs',
      dockerController.getContainerLogs,
    );
    router.delete('/api/docker/images/<id>', dockerController.removeImage);

    return router;
  }
}
