import 'package:shelf_router/shelf_router.dart';

import 'package:host_deck/server/features/agent/agent_controller.dart';

void registerAgentRoutes(Router router, AgentController controller) {
  router.get('/api/agent/discovery', controller.discovery);
  router.get('/api/agent/sessions', controller.listSessions);
  router.post('/api/agent/exec', controller.exec);
  router.post('/api/agent/file/read', controller.readFile);
  router.post('/api/agent/file/write', controller.writeFile);
  router.post('/api/agent/patch', controller.applyPatch);
}
