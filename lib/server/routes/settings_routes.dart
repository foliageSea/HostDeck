import 'package:shelf_router/shelf_router.dart';

import 'package:host_deck/server/features/settings/settings_controller.dart';

void registerSettingsRoutes(Router router, SettingsController controller) {
  router.get('/api/settings/tls', controller.getTlsSettings);
  router.put('/api/settings/tls', controller.saveTlsSettings);
  router.get(
    '/api/settings/tls/certificate',
    controller.downloadTlsCertificate,
  );
  router.get('/api/settings/version', controller.getServiceVersion);
  router.get('/api/settings/ports', controller.getBackendPorts);
  router.get('/api/settings/ui', controller.getUiSettings);
  router.put('/api/settings/ui', controller.saveUiSettings);
  router.post('/api/settings/ui/wallpapers', controller.uploadWallpaper);
  router.get('/api/settings/logs/export', controller.exportLogs);
}
