import 'package:shelf_router/shelf_router.dart';

import 'package:host_deck/server/features/auth/auth_controller.dart';

void registerAuthRoutes(Router router, AuthController controller) {
  router.post('/api/connect', controller.connect);
  router.post('/api/connect/test', controller.testConnect);
  router.delete('/api/connect', controller.disconnect);
}
