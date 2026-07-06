import 'package:shelf_router/shelf_router.dart';

import 'package:host_deck/server/features/operation_logs/operation_log_controller.dart';

void registerOperationLogRoutes(
  Router router,
  OperationLogController controller,
) {
  router.get('/api/operation-logs', controller.list);
  router.delete('/api/operation-logs', controller.clear);
}
