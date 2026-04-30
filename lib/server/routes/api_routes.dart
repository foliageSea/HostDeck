import 'package:shelf_router/shelf_router.dart';
import '../controllers/auth_controller.dart';
import '../controllers/system_controller.dart';
import '../controllers/file_controller.dart';
import '../controllers/terminal_controller.dart';
import '../controllers/server_controller.dart';
import '../controllers/docker_controller.dart';
import '../controllers/runtime_controller.dart';

class ApiRoutes {
  final AuthController authController;
  final SystemController systemController;
  final FileController fileController;
  final TerminalController terminalController;
  final ServerController serverController;
  final DockerController dockerController;
  final RuntimeController runtimeController;

  ApiRoutes({
    required this.authController,
    required this.systemController,
    required this.fileController,
    required this.terminalController,
    required this.serverController,
    required this.dockerController,
    required this.runtimeController,
  });

  Router get router {
    final router = Router();

    // Auth
    router.post('/api/connect', authController.connect);
    router.delete('/api/connect', authController.disconnect);

    // Servers
    router.get('/api/servers', serverController.list);
    router.post('/api/servers', serverController.create);
    router.put('/api/servers/<id>', serverController.update);
    router.delete('/api/servers/<id>', serverController.delete);

    // Runtime
    router.get('/api/runtime/sessions', runtimeController.listSessions);
    router.get('/api/ws/runtime', runtimeController.wsSessions);

    // System
    router.get('/api/status', systemController.status);
    router.get('/api/ws/monitor', systemController.wsMonitor);
    router.get('/api/ws/session', systemController.wsSessionStatus);

    // Files
    router.get('/api/files/list', fileController.listFiles);
    router.post('/api/files/session', fileController.createSession);
    router.delete('/api/files/session', fileController.closeSession);
    router.get('/api/files/read', fileController.readFile);
    router.post('/api/files/write', fileController.writeFile);
    router.post('/api/files/delete', fileController.deleteFile);
    router.post('/api/files/upload', fileController.uploadFile);
    router.post('/api/files/batch-download', fileController.batchDownload);
    router.post('/api/files/rename', fileController.rename);
    router.post('/api/files/mkdir', fileController.mkdir);
    router.post('/api/files/copy', fileController.copy);
    router.post('/api/files/extract', fileController.extract);

    // Terminal
    router.get('/socket.io', terminalController.handler);
    router.post('/api/terminal/session', terminalController.createSession);
    router.delete('/api/terminal/session', terminalController.closeSession);

    // Docker
    router.post('/api/docker/session', dockerController.createSession);
    router.delete('/api/docker/session', dockerController.closeSession);
    router.get('/api/docker/check', dockerController.checkDocker);
    router.get('/api/docker/compose/check', dockerController.checkCompose);
    router.get(
      '/api/docker/compose/projects',
      dockerController.listComposeProjects,
    );
    router.post(
      '/api/docker/compose/project',
      dockerController.createComposeProject,
    );
    router.post(
      '/api/docker/compose/project/services',
      dockerController.listComposeServices,
    );
    router.post(
      '/api/docker/compose/project/up',
      dockerController.upComposeProject,
    );
    router.post(
      '/api/docker/compose/project/stop',
      dockerController.stopComposeProject,
    );
    router.post(
      '/api/docker/compose/project/restart',
      dockerController.restartComposeProject,
    );
    router.post(
      '/api/docker/compose/project/down',
      dockerController.downComposeProject,
    );
    router.post(
      '/api/docker/compose/project/logs',
      dockerController.getComposeLogs,
    );
    router.get('/api/docker/containers', dockerController.listContainers);
    router.get(
      '/api/docker/containers/<id>/inspect',
      dockerController.inspectContainer,
    );
    router.get(
      '/api/docker/containers/<id>/stats',
      dockerController.getContainerStats,
    );
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
    router.post(
      '/api/docker/containers/<id>/pause',
      dockerController.pauseContainer,
    );
    router.post(
      '/api/docker/containers/<id>/unpause',
      dockerController.unpauseContainer,
    );
    router.post(
      '/api/docker/containers/<id>/rename',
      dockerController.renameContainer,
    );
    router.post(
      '/api/docker/containers/<id>/recreate',
      dockerController.recreateContainer,
    );
    router.delete(
      '/api/docker/containers/<id>',
      dockerController.removeContainer,
    );
    router.post('/api/docker/containers', dockerController.createContainer);
    router.get(
      '/api/docker/containers/logs',
      dockerController.getContainerLogs,
    );
    router.post(
      '/api/docker/containers/diagnostics',
      dockerController.getContainerDiagnostics,
    );
    router.post(
      '/api/docker/containers/batch-start',
      dockerController.batchStartContainers,
    );
    router.post(
      '/api/docker/containers/batch-stop',
      dockerController.batchStopContainers,
    );
    router.delete(
      '/api/docker/containers/stopped',
      dockerController.removeStoppedContainers,
    );
    router.post('/api/docker/images/prune', dockerController.pruneImages);
    router.delete('/api/docker/images/<id>', dockerController.removeImage);
    router.post('/api/docker/images/pull', dockerController.pullImage);
    router.post('/api/docker/images/tag', dockerController.tagImage);
    router.get(
      '/api/docker/images/<id>/history',
      dockerController.getImageHistory,
    );
    router.get(
      '/api/docker/images/<id>/create-defaults',
      dockerController.getImageCreateDefaults,
    );
    router.get(
      '/api/docker/images/<id>/containers',
      dockerController.getImageContainers,
    );

    return router;
  }
}
