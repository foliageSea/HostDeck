import 'package:shelf_router/shelf_router.dart';

import 'package:host_deck/server/features/crontabs/cron_task_controller.dart';

void registerCronTaskRoutes(Router router, CronTaskController controller) {
  router.get('/api/cron-tasks', controller.list);
  router.post('/api/cron-tasks', controller.create);
  router.put('/api/cron-tasks/<id>', controller.update);
  router.delete('/api/cron-tasks/<id>', controller.delete);
  router.post('/api/cron-tasks/<id>/run', controller.runNow);
  router.get('/api/cron-tasks/<id>/history', controller.listHistory);
  router.post('/api/cron-tasks/<id>/history/sync', controller.syncHistory);
}
