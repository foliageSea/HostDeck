import 'package:shelf_router/shelf_router.dart';

import 'package:host_deck/server/features/servers/server_controller.dart';

void registerServerRoutes(Router router, ServerController controller) {
  router.get('/api/servers', controller.list);
  router.post('/api/servers', controller.create);
  router.put('/api/servers/<id>', controller.update);
  router.delete('/api/servers/<id>', controller.delete);
}
