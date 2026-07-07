import 'package:logging/logging.dart';

import 'package:host_deck/server/core/database/database_service.dart';
import 'package:host_deck/server/core/ssh/ssh_repository.dart';
import 'package:host_deck/server/core/ssh/ssh_service.dart';
import 'package:host_deck/server/features/agent/agent_controller.dart';
import 'package:host_deck/server/features/agent/agent_service.dart';
import 'package:host_deck/server/features/auth/auth_controller.dart';
import 'package:host_deck/server/features/docker/docker_controller.dart';
import 'package:host_deck/server/features/docker/docker_service.dart';
import 'package:host_deck/server/features/files/file_controller.dart';
import 'package:host_deck/server/features/files/file_service.dart';
import 'package:host_deck/server/features/operation_logs/operation_log_controller.dart';
import 'package:host_deck/server/features/operation_logs/operation_log_repository.dart';
import 'package:host_deck/server/features/operation_logs/operation_log_service.dart';
import 'package:host_deck/server/features/port_forwards/port_forward_controller.dart';
import 'package:host_deck/server/features/port_forwards/port_forward_repository.dart';
import 'package:host_deck/server/features/port_forwards/port_forward_service.dart';
import 'package:host_deck/server/features/processes/process_controller.dart';
import 'package:host_deck/server/features/processes/process_service.dart';
import 'package:host_deck/server/features/runtime/runtime_controller.dart';
import 'package:host_deck/server/features/servers/server_controller.dart';
import 'package:host_deck/server/features/servers/server_repository.dart';
import 'package:host_deck/server/features/settings/settings_controller.dart';
import 'package:host_deck/server/features/system/monitor_history_service.dart';
import 'package:host_deck/server/features/system/monitor_service.dart';
import 'package:host_deck/server/features/system/system_controller.dart';
import 'package:host_deck/server/features/terminal/terminal_controller.dart';
import 'package:host_deck/server/routes/api_routes.dart';
import 'package:host_deck/utils/app_settings.dart';

class ServerContainer {
  final DatabaseService databaseService;
  final PortForwardService portForwardService;
  final ApiRoutes apiRoutes;

  ServerContainer._({
    required this.databaseService,
    required this.portForwardService,
    required this.apiRoutes,
  });

  static Future<ServerContainer> create({
    required String? dataDir,
    required Logger log,
  }) async {
    final databaseService = DatabaseService(dataDir: dataDir);
    AppSettings.configure(dataDir: dataDir);
    try {
      await databaseService.init();
      log.info('Database initialized.');
    } catch (e) {
      log.severe('Database initialization failed: $e');
    }

    final sshRepository = SshRepository();
    final serverRepository = ServerRepository(databaseService);
    final portForwardRepository = PortForwardRepository(databaseService);
    final operationLogRepository = OperationLogRepository(databaseService);
    final operationLogService = OperationLogService(operationLogRepository);
    final sshService = SshService();
    final monitorHistoryService = MonitorHistoryService();
    final monitorService = MonitorService(sshRepository);
    final agentService = AgentService(sshRepository);
    final fileService = FileService(sshRepository);
    final dockerService = DockerService(sshRepository);
    final processService = ProcessService(sshRepository);
    portForwardRepository.setAllDisabled();
    final portForwardService = PortForwardService(
      sshService,
      onRunningChanged: portForwardRepository.setEnabled,
    );

    return ServerContainer._(
      databaseService: databaseService,
      portForwardService: portForwardService,
      apiRoutes: ApiRoutes(
        authController: AuthController(
          sshService,
          monitorHistoryService,
          serverRepository,
          operationLogService,
        ),
        agentController: AgentController(
          sshService,
          agentService,
          operationLogService,
        ),
        systemController: SystemController(
          sshService,
          monitorService,
          monitorHistoryService,
        ),
        fileController: FileController(
          sshService,
          fileService,
          operationLogService,
        ),
        operationLogController: OperationLogController(operationLogRepository),
        terminalController: TerminalController(sshService),
        serverController: ServerController(
          serverRepository,
          operationLogService,
        ),
        dockerController: DockerController(
          sshService,
          dockerService,
          operationLogService,
        ),
        processController: ProcessController(
          sshService,
          processService,
          operationLogService,
        ),
        runtimeController: RuntimeController(sshService),
        settingsController: SettingsController(),
        portForwardController: PortForwardController(
          portForwardRepository,
          portForwardService,
          operationLogService,
        ),
      ),
    );
  }
}
