import 'package:shelf_router/shelf_router.dart';

import 'package:host_deck/server/features/files/file_controller.dart';

void registerFileRoutes(Router router, FileController controller) {
  router.get('/api/files/list', controller.listFiles);
  router.get('/api/files/directory-size', controller.directorySize);
  router.post('/api/files/session', controller.createSession);
  router.delete('/api/files/session', controller.closeSession);
  router.get('/api/files/read', controller.readFile);
  router.post('/api/files/write', controller.writeFile);
  router.post('/api/files/delete', controller.deleteFile);
  router.post('/api/files/upload', controller.uploadFile);
  router.post('/api/files/batch-download', controller.batchDownload);
  router.post('/api/files/rename', controller.rename);
  router.post('/api/files/mkdir', controller.mkdir);
  router.post('/api/files/chmod', controller.chmod);
  router.post('/api/files/copy', controller.copy);
  router.post('/api/files/extract', controller.extract);
}
