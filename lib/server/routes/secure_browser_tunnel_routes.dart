import 'package:shelf_router/shelf_router.dart';

import 'package:host_deck/server/features/port_forwards/secure_browser_tunnel_controller.dart';

void registerSecureBrowserTunnelRoutes(
  Router router,
  SecureBrowserTunnelController controller,
) {
  router.get('/api/secure-browser-tunnels', controller.list);
  router.get(
    '/api/secure-browser-tunnels/capabilities',
    controller.capabilities,
  );
  router.post('/api/secure-browser-tunnels', controller.create);
  router.post('/api/secure-browser-tunnels/<id>/launch', controller.launch);
  router.delete('/api/secure-browser-tunnels/<id>', controller.stop);
}
