import 'package:shelf_router/shelf_router.dart';

import 'package:host_deck/server/features/auth/auth_controller.dart';
import 'package:host_deck/server/features/docker/docker_controller.dart';
import 'package:host_deck/server/features/files/file_controller.dart';
import 'package:host_deck/server/features/port_forwards/port_forward_controller.dart';
import 'package:host_deck/server/features/processes/process_controller.dart';
import 'package:host_deck/server/features/runtime/runtime_controller.dart';
import 'package:host_deck/server/features/servers/server_controller.dart';
import 'package:host_deck/server/features/settings/settings_controller.dart';
import 'package:host_deck/server/features/system/system_controller.dart';
import 'package:host_deck/server/features/terminal/terminal_controller.dart';
import 'package:host_deck/server/routes/auth_routes.dart';
import 'package:host_deck/server/routes/docker_routes.dart';
import 'package:host_deck/server/routes/file_routes.dart';
import 'package:host_deck/server/routes/port_forward_routes.dart';
import 'package:host_deck/server/routes/process_routes.dart';
import 'package:host_deck/server/routes/runtime_routes.dart';
import 'package:host_deck/server/routes/server_routes.dart';
import 'package:host_deck/server/routes/settings_routes.dart';
import 'package:host_deck/server/routes/system_routes.dart';
import 'package:host_deck/server/routes/terminal_routes.dart';

class ApiRoutes {
  final AuthController authController;
  final SystemController systemController;
  final FileController fileController;
  final TerminalController terminalController;
  final ServerController serverController;
  final DockerController dockerController;
  final ProcessController processController;
  final RuntimeController runtimeController;
  final SettingsController settingsController;
  final PortForwardController portForwardController;

  ApiRoutes({
    required this.authController,
    required this.systemController,
    required this.fileController,
    required this.terminalController,
    required this.serverController,
    required this.dockerController,
    required this.processController,
    required this.runtimeController,
    required this.settingsController,
    required this.portForwardController,
  });

  Router get router {
    final router = Router();
    registerAuthRoutes(router, authController);
    registerServerRoutes(router, serverController);
    registerRuntimeRoutes(router, runtimeController);
    registerSettingsRoutes(router, settingsController);
    registerPortForwardRoutes(router, portForwardController);
    registerSystemRoutes(router, systemController);
    registerProcessRoutes(router, processController);
    registerFileRoutes(router, fileController);
    registerTerminalRoutes(router, terminalController);
    registerDockerRoutes(router, dockerController);
    return router;
  }
}
