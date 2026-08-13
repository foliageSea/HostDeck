import 'package:shelf_router/shelf_router.dart';

import 'package:host_deck/server/features/logs/server_log_controller.dart';

void registerLogRoutes(Router router, ServerLogController controller) {
  router.get('/api/logs/stream', controller.stream);
}
