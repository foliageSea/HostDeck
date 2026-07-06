import 'package:shelf_router/shelf_router.dart';

import 'package:host_deck/server/features/port_forwards/port_forward_controller.dart';

void registerPortForwardRoutes(
  Router router,
  PortForwardController controller,
) {
  router.get('/api/port-forwards', controller.list);
  router.post('/api/port-forwards', controller.create);
  router.put('/api/port-forwards/<id>', controller.update);
  router.delete('/api/port-forwards/<id>', controller.delete);
  router.post('/api/port-forwards/<id>/start', controller.start);
  router.post('/api/port-forwards/<id>/stop', controller.stop);
}
