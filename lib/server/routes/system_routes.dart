import 'package:shelf_router/shelf_router.dart';

import 'package:host_deck/server/features/system/system_controller.dart';

void registerSystemRoutes(Router router, SystemController controller) {
  router.get('/api/status', controller.status);
  router.get('/api/system/monitor/history', controller.history);
  router.get('/api/ws/monitor', controller.wsMonitor);
  router.get('/api/ws/session', controller.wsSessionStatus);
}
