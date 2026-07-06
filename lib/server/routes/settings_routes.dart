import 'package:shelf_router/shelf_router.dart';

import 'package:host_deck/server/features/settings/settings_controller.dart';

void registerSettingsRoutes(Router router, SettingsController controller) {
  router.get('/api/settings/ui', controller.getUiSettings);
  router.put('/api/settings/ui', controller.saveUiSettings);
  router.post('/api/settings/ui/wallpapers', controller.uploadWallpaper);
}
