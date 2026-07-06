import 'package:shelf_router/shelf_router.dart';

import 'package:host_deck/server/features/processes/process_controller.dart';

void registerProcessRoutes(Router router, ProcessController controller) {
  router.get('/api/processes', controller.list);
  router.post('/api/processes/<pid>/kill', controller.kill);
}
