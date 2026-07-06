import 'package:shelf_router/shelf_router.dart';

import 'package:host_deck/server/features/terminal/terminal_controller.dart';

void registerTerminalRoutes(Router router, TerminalController controller) {
  router.get('/api/ws/terminal', controller.handler);
  router.post('/api/terminal/session', controller.createSession);
  router.delete('/api/terminal/session', controller.closeSession);
}
