import 'package:shelf_router/shelf_router.dart';

import 'package:host_deck/server/features/runtime/runtime_controller.dart';

void registerRuntimeRoutes(Router router, RuntimeController controller) {
  router.get('/api/runtime/sessions', controller.listSessions);
  router.get('/api/runtime/sessions/stream', controller.streamSessions);
}
