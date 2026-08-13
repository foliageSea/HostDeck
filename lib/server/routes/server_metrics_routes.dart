import 'package:shelf_router/shelf_router.dart';

import 'package:host_deck/server/features/server_metrics/server_metrics_controller.dart';

void registerServerMetricsRoutes(
  Router router,
  ServerMetricsController controller,
) {
  router.get('/api/server/metrics', controller.snapshot);
  router.get('/api/ws/server-metrics', controller.wsMetrics);
}
