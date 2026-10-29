import 'package:shelf_router/shelf_router.dart';

import 'package:host_deck/server/features/code_server/code_server_controller.dart';

void registerCodeServerRoutes(Router router, CodeServerController controller) {
  router.get('/api/code-server/packages', controller.listPackages);
  router.post('/api/code-server/packages', controller.uploadPackage);
  router.delete('/api/code-server/packages/<id>', controller.deletePackage);
  router.post('/api/code-server/packages/scan', controller.scanPackages);
  router.get('/api/code-server/targets/<cid>/status', controller.status);
  router.post('/api/code-server/targets/<cid>/install', controller.install);
  router.post('/api/code-server/targets/<cid>/start', controller.start);
  router.post('/api/code-server/targets/<cid>/stop', controller.stop);
}
