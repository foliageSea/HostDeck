import 'package:shelf_router/shelf_router.dart';

import 'package:host_deck/server/features/ai_agent/ai_agent_controller.dart';

void registerAiAgentRoutes(Router router, AiAgentController controller) {
  router.get('/api/ai-agent/settings', controller.getSettings);
  router.put('/api/ai-agent/settings', controller.updateSettings);
  router.post('/api/ai-agent/settings/test', controller.testSettings);
  router.get('/api/ai-agent/conversations', controller.listConversations);
  router.post('/api/ai-agent/conversations', controller.createConversation);
  router.get('/api/ai-agent/conversations/<id>', controller.getConversation);
  router.delete(
    '/api/ai-agent/conversations/<id>',
    controller.deleteConversation,
  );
  router.post('/api/ai-agent/conversations/<id>/runs', controller.run);
  router.post('/api/ai-agent/runs/<id>/approve', controller.approve);
  router.post('/api/ai-agent/runs/<id>/reject', controller.reject);
  router.delete('/api/ai-agent/runs/<id>', controller.cancel);
}
