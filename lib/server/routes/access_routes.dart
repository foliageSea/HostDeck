import 'package:shelf_router/shelf_router.dart';

import 'package:host_deck/server/features/access/access_controller.dart';

void registerAccessRoutes(Router router, AccessController controller) {
  router.get('/api/access/state', controller.state);
  router.post('/api/access/login', controller.login);
  router.post('/api/access/logout', controller.logout);
}
