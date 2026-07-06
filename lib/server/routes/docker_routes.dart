import 'package:shelf_router/shelf_router.dart';

import 'package:host_deck/server/features/docker/docker_controller.dart';

void registerDockerRoutes(Router router, DockerController controller) {
  router.post('/api/docker/session', controller.createSession);
  router.delete('/api/docker/session', controller.closeSession);
  router.get('/api/docker/check', controller.checkDocker);
  router.get('/api/docker/compose/check', controller.checkCompose);
  router.get('/api/docker/compose/projects', controller.listComposeProjects);
  router.post('/api/docker/compose/project', controller.createComposeProject);
  router.post(
    '/api/docker/compose/project/services',
    controller.listComposeServices,
  );
  router.post('/api/docker/compose/project/up', controller.upComposeProject);
  router.post(
    '/api/docker/compose/project/stop',
    controller.stopComposeProject,
  );
  router.post(
    '/api/docker/compose/project/restart',
    controller.restartComposeProject,
  );
  router.post(
    '/api/docker/compose/project/down',
    controller.downComposeProject,
  );
  router.post('/api/docker/compose/project/logs', controller.getComposeLogs);
  router.get('/api/docker/containers', controller.listContainers);
  router.get(
    '/api/docker/containers/<id>/inspect',
    controller.inspectContainer,
  );
  router.get('/api/docker/containers/<id>/stats', controller.getContainerStats);
  router.post(
    '/api/docker/containers/<id>/shell',
    controller.createContainerShellSession,
  );
  router.get('/api/docker/images', controller.listImages);
  router.get('/api/docker/networks', controller.listNetworks);
  router.post('/api/docker/networks', controller.createNetwork);
  router.get('/api/docker/networks/<id>/inspect', controller.inspectNetwork);
  router.post('/api/docker/networks/<id>/connect', controller.connectNetwork);
  router.post(
    '/api/docker/networks/<id>/disconnect',
    controller.disconnectNetwork,
  );
  router.delete('/api/docker/networks/<id>', controller.removeNetwork);
  router.post('/api/docker/networks/prune', controller.pruneNetworks);
  router.get('/api/docker/volumes', controller.listVolumes);
  router.post('/api/docker/volumes', controller.createVolume);
  router.get('/api/docker/volumes/<name>/inspect', controller.inspectVolume);
  router.delete('/api/docker/volumes/<name>', controller.removeVolume);
  router.post('/api/docker/volumes/prune', controller.pruneVolumes);
  router.post('/api/docker/build-cache/prune', controller.pruneBuildCache);
  router.post('/api/docker/containers/<id>/start', controller.startContainer);
  router.post('/api/docker/containers/<id>/stop', controller.stopContainer);
  router.post(
    '/api/docker/containers/<id>/restart',
    controller.restartContainer,
  );
  router.post('/api/docker/containers/<id>/pause', controller.pauseContainer);
  router.post(
    '/api/docker/containers/<id>/unpause',
    controller.unpauseContainer,
  );
  router.post('/api/docker/containers/<id>/rename', controller.renameContainer);
  router.post(
    '/api/docker/containers/<id>/recreate',
    controller.recreateContainer,
  );
  router.delete('/api/docker/containers/<id>', controller.removeContainer);
  router.post('/api/docker/containers', controller.createContainer);
  router.get('/api/docker/containers/logs', controller.getContainerLogs);
  router.post(
    '/api/docker/containers/diagnostics',
    controller.getContainerDiagnostics,
  );
  router.post(
    '/api/docker/containers/batch-start',
    controller.batchStartContainers,
  );
  router.post(
    '/api/docker/containers/batch-stop',
    controller.batchStopContainers,
  );
  router.delete(
    '/api/docker/containers/stopped',
    controller.removeStoppedContainers,
  );
  router.post('/api/docker/images/prune', controller.pruneImages);
  router.delete('/api/docker/images/<id>', controller.removeImage);
  router.post('/api/docker/images/pull', controller.pullImage);
  router.post('/api/docker/images/import', controller.importImage);
  router.post('/api/docker/images/tag', controller.tagImage);
  router.get('/api/docker/images/<id>/export', controller.exportImage);
  router.get('/api/docker/images/<id>/history', controller.getImageHistory);
  router.get(
    '/api/docker/images/<id>/create-defaults',
    controller.getImageCreateDefaults,
  );
  router.get(
    '/api/docker/images/<id>/containers',
    controller.getImageContainers,
  );
}
