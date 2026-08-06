import 'dart:io';

import 'package:logging/logging.dart';

import 'package:host_deck/server/core/database/database_service.dart';
import 'package:host_deck/server/core/ssh/ssh_repository.dart';
import 'package:host_deck/server/core/ssh/ssh_service.dart';
import 'package:host_deck/server/features/agent/agent_controller.dart';
import 'package:host_deck/server/features/access/access_controller.dart';
import 'package:host_deck/server/features/access/access_auth_service.dart';
import 'package:host_deck/server/features/agent/agent_service.dart';
import 'package:host_deck/server/features/auth/auth_controller.dart';
import 'package:host_deck/server/features/docker/docker_compose_service.dart';
import 'package:host_deck/server/features/docker/docker_container_service.dart';
import 'package:host_deck/server/features/docker/docker_controller.dart';
import 'package:host_deck/server/features/docker/docker_engine_mapper.dart';
import 'package:host_deck/server/features/docker/docker_engine_repository.dart';
import 'package:host_deck/server/features/docker/docker_image_service.dart';
import 'package:host_deck/server/features/docker/docker_resource_service.dart';
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
import 'package:host_deck/server/features/settings/log_export_service.dart';
import 'package:host_deck/server/features/settings/settings_controller.dart';
import 'package:host_deck/server/features/system/monitor_history_service.dart';
import 'package:host_deck/server/features/system/monitor_service.dart';
import 'package:host_deck/server/features/system/system_controller.dart';
import 'package:host_deck/server/features/terminal/terminal_controller.dart';
import 'package:host_deck/server/features/terminal/terminal_snippet_repository.dart';
import 'package:host_deck/server/routes/api_routes.dart';
import 'package:host_deck/utils/app_settings.dart';

class ServerContainer {
  final DatabaseService databaseService;
  final PortForwardService portForwardService;
  final ApiRoutes apiRoutes;
  final AccessAuthService accessService;
  final OperationLogService operationLogService;
  final PortForwardRepository portForwardRepository;
  final ServerRepository serverRepository;

  ServerContainer._({
    required this.databaseService,
    required this.portForwardService,
    required this.apiRoutes,
    required this.accessService,
    required this.operationLogService,
    required this.portForwardRepository,
    required this.serverRepository,
  });

  static Future<ServerContainer> create({
    required String? dataDir,
    String? logDir,
    Future<void> Function()? flushLogs,
    required Logger log,
    String? adminPassword,
    String? apiToken,
    bool secureCookies = false,
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
    final accessService = AccessAuthService(
      password: adminPassword,
      apiToken: apiToken,
      secureCookies: secureCookies,
    );
    final serverRepository = ServerRepository(databaseService);
    final portForwardRepository = PortForwardRepository(databaseService);
    final operationLogRepository = OperationLogRepository(databaseService);
    final terminalSnippetRepository = TerminalSnippetRepository(
      databaseService,
    );
    final operationLogService = OperationLogService(operationLogRepository);
    final sshService = SshService();
    final monitorHistoryService = MonitorHistoryService();
    final monitorService = MonitorService(sshRepository);
    final agentService = AgentService(sshRepository);
    final fileService = FileService(sshRepository);
    final dockerEngineRepository = DockerEngineRepository(sshRepository);
    final dockerEngineMapper = DockerEngineMapper();
    final dockerContainerService = DockerContainerService(
      dockerEngineRepository,
      dockerEngineMapper,
    );
    final dockerImageService = DockerImageService(
      dockerEngineRepository,
      dockerEngineMapper,
    );
    final dockerResourceService = DockerResourceService(
      dockerEngineRepository,
      dockerEngineMapper,
    );
    final dockerComposeService = DockerComposeService(sshRepository);
    final processService = ProcessService(sshRepository);
    portForwardRepository.setAllDisabled();
    final portForwardService = PortForwardService(
      sshService,
      onRunningChanged: portForwardRepository.setEnabled,
    );

    return ServerContainer._(
      databaseService: databaseService,
      portForwardService: portForwardService,
      accessService: accessService,
      operationLogService: operationLogService,
      portForwardRepository: portForwardRepository,
      serverRepository: serverRepository,
      apiRoutes: ApiRoutes(
        accessController: AccessController(accessService),
        authController: AuthController(
          sshService,
          monitorHistoryService,
          serverRepository,
        ),
        agentController: AgentController(sshService, agentService),
        systemController: SystemController(
          sshService,
          monitorService,
          monitorHistoryService,
        ),
        fileController: FileController(sshService, fileService),
        operationLogController: OperationLogController(operationLogRepository),
        terminalController: TerminalController(
          sshService,
          terminalSnippetRepository,
        ),
        serverController: ServerController(serverRepository),
        dockerController: DockerController(
          sshService,
          dockerContainerService,
          dockerImageService,
          dockerResourceService,
          dockerComposeService,
        ),
        processController: ProcessController(sshService, processService),
        runtimeController: RuntimeController(sshService),
        settingsController: SettingsController(
          LogExportService(
            logDirectory: logDir == null ? null : Directory(logDir),
            flushLogs: flushLogs,
            log: log,
          ),
        ),
        portForwardController: PortForwardController(
          portForwardRepository,
          portForwardService,
        ),
      ),
    );
  }
}
