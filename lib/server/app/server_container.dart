import 'dart:io';

import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';

import 'package:host_deck/server/core/database/database_service.dart';
import 'package:host_deck/server/core/ssh/ssh_repository.dart';
import 'package:host_deck/server/core/ssh/ssh_service.dart';
import 'package:host_deck/server/features/agent/agent_controller.dart';
import 'package:host_deck/server/features/access/access_controller.dart';
import 'package:host_deck/server/features/access/access_auth_service.dart';
import 'package:host_deck/server/features/agent/agent_service.dart';
import 'package:host_deck/server/features/auth/auth_controller.dart';
import 'package:host_deck/server/features/crontabs/cron_task_controller.dart';
import 'package:host_deck/server/features/crontabs/cron_task_repository.dart';
import 'package:host_deck/server/features/crontabs/cron_task_service.dart';
import 'package:host_deck/server/features/docker/docker_container_service.dart';
import 'package:host_deck/server/features/docker/docker_compose_service.dart';
import 'package:host_deck/server/features/docker/docker_controller.dart';
import 'package:host_deck/server/features/docker/docker_engine_mapper.dart';
import 'package:host_deck/server/features/docker/docker_engine_repository.dart';
import 'package:host_deck/server/features/docker/docker_image_service.dart';
import 'package:host_deck/server/features/docker/docker_resource_service.dart';
import 'package:host_deck/server/features/docker/docker_socket_tunnel_service.dart';
import 'package:host_deck/server/features/files/file_controller.dart';
import 'package:host_deck/server/features/files/file_service.dart';
import 'package:host_deck/server/features/logs/server_log_controller.dart';
import 'package:host_deck/server/features/logs/server_log_service.dart';
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
import 'package:host_deck/server/features/server_metrics/server_metrics_controller.dart';
import 'package:host_deck/server/features/server_metrics/server_metrics_service.dart';
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
  final GetIt _getIt;
  final DatabaseService databaseService;
  final PortForwardService portForwardService;
  final DockerSocketTunnelService dockerSocketTunnelService;
  final ApiRoutes apiRoutes;
  final AccessAuthService accessService;
  final OperationLogService operationLogService;
  final PortForwardRepository portForwardRepository;
  final ServerRepository serverRepository;

  ServerContainer._({
    required GetIt getIt,
    required this.databaseService,
    required this.portForwardService,
    required this.dockerSocketTunnelService,
    required this.apiRoutes,
    required this.accessService,
    required this.operationLogService,
    required this.portForwardRepository,
    required this.serverRepository,
  }) : _getIt = getIt;

  static Future<ServerContainer> create({
    required String? dataDir,
    String? logDir,
    Future<void> Function()? flushLogs,
    required Logger log,
    String? adminPassword,
    String? apiToken,
    bool secureCookies = false,
    required ServerLogService logService,
  }) async {
    AppSettings.configure(dataDir: dataDir);
    final getIt = GetIt.asNewInstance();
    getIt.registerSingleton<ServerLogService>(logService);

    getIt.registerSingletonAsync<DatabaseService>(() async {
      final databaseService = DatabaseService(dataDir: dataDir);
      try {
        await databaseService.init();
        log.info('Database initialized.');
      } catch (e) {
        log.severe('Database initialization failed: $e');
      }
      return databaseService;
    });
    getIt.registerLazySingleton<SshRepository>(SshRepository.new);
    getIt.registerLazySingleton<SshService>(SshService.new);
    getIt.registerLazySingleton<AccessAuthService>(
      () => AccessAuthService(
        password: adminPassword,
        apiToken: apiToken,
        secureCookies: secureCookies,
      ),
    );
    getIt.registerLazySingleton<ServerRepository>(
      () => ServerRepository(getIt<DatabaseService>()),
    );
    getIt.registerLazySingleton<PortForwardRepository>(
      () => PortForwardRepository(getIt<DatabaseService>()),
    );
    getIt.registerLazySingleton<OperationLogRepository>(
      () => OperationLogRepository(getIt<DatabaseService>()),
    );
    getIt.registerLazySingleton<TerminalSnippetRepository>(
      () => TerminalSnippetRepository(getIt<DatabaseService>()),
    );
    getIt.registerLazySingleton<CronTaskRepository>(
      () => CronTaskRepository(getIt<DatabaseService>()),
    );
    getIt.registerLazySingleton<OperationLogService>(
      () => OperationLogService(getIt<OperationLogRepository>()),
    );
    getIt.registerLazySingleton<MonitorHistoryService>(
      MonitorHistoryService.new,
    );
    getIt.registerLazySingleton<MonitorService>(
      () => MonitorService(getIt<SshRepository>()),
    );
    getIt.registerLazySingleton<ServerMetricsService>(
      ServerMetricsService.new,
      dispose: (service) => service.dispose(),
    );
    getIt.registerLazySingleton<CronTaskService>(
      () =>
          CronTaskService(getIt<SshRepository>(), getIt<CronTaskRepository>()),
    );
    getIt.registerLazySingleton<AgentService>(
      () => AgentService(getIt<SshRepository>()),
    );
    getIt.registerLazySingleton<FileService>(
      () => FileService(getIt<SshRepository>()),
    );
    getIt.registerLazySingleton<DockerSocketTunnelService>(
      DockerSocketTunnelService.new,
    );
    getIt.registerLazySingleton<DockerEngineRepository>(
      () => DockerEngineRepository(
        tunnelService: getIt<DockerSocketTunnelService>(),
      ),
      dispose: (repository) => repository.close(),
    );
    getIt.registerLazySingleton<DockerEngineMapper>(DockerEngineMapper.new);
    getIt.registerLazySingleton<DockerComposeService>(
      () => DockerComposeService(getIt<SshRepository>()),
    );
    getIt.registerLazySingleton<DockerContainerService>(
      () => DockerContainerService(
        getIt<DockerEngineRepository>(),
        getIt<DockerEngineMapper>(),
      ),
    );
    getIt.registerLazySingleton<DockerImageService>(
      () => DockerImageService(
        getIt<DockerEngineRepository>(),
        getIt<DockerEngineMapper>(),
      ),
    );
    getIt.registerLazySingleton<DockerResourceService>(
      () => DockerResourceService(
        getIt<DockerEngineRepository>(),
        getIt<DockerEngineMapper>(),
      ),
    );
    getIt.registerLazySingleton<ProcessService>(
      () => ProcessService(getIt<SshRepository>()),
    );
    getIt.registerLazySingleton<PortForwardService>(
      () => PortForwardService(
        getIt<SshService>(),
        onRunningChanged: getIt<PortForwardRepository>().setEnabled,
      ),
    );
    getIt.registerLazySingleton<LogExportService>(
      () => LogExportService(
        logDirectory: logDir == null ? null : Directory(logDir),
        flushLogs: flushLogs,
        log: log,
      ),
    );
    getIt.registerLazySingleton<ApiRoutes>(
      () => ApiRoutes(
        accessController: AccessController(getIt<AccessAuthService>()),
        authController: AuthController(
          getIt<SshService>(),
          getIt<MonitorHistoryService>(),
          getIt<ServerRepository>(),
        ),
        agentController: AgentController(
          getIt<SshService>(),
          getIt<AgentService>(),
        ),
        systemController: SystemController(
          getIt<SshService>(),
          getIt<MonitorService>(),
          getIt<MonitorHistoryService>(),
        ),
        fileController: FileController(
          getIt<SshService>(),
          getIt<FileService>(),
        ),
        operationLogController: OperationLogController(
          getIt<OperationLogRepository>(),
        ),
        serverLogController: ServerLogController(getIt<ServerLogService>()),
        terminalController: TerminalController(
          getIt<SshService>(),
          getIt<TerminalSnippetRepository>(),
        ),
        serverController: ServerController(getIt<ServerRepository>()),
        dockerController: DockerController(
          getIt<SshService>(),
          getIt<DockerContainerService>(),
          getIt<DockerImageService>(),
          getIt<DockerResourceService>(),
          getIt<DockerComposeService>(),
        ),
        cronTaskController: CronTaskController(
          getIt<SshService>(),
          getIt<CronTaskRepository>(),
          getIt<CronTaskService>(),
        ),
        processController: ProcessController(
          getIt<SshService>(),
          getIt<ProcessService>(),
        ),
        runtimeController: RuntimeController(getIt<SshService>()),
        serverMetricsController: ServerMetricsController(
          getIt<ServerMetricsService>(),
        ),
        settingsController: SettingsController(getIt<LogExportService>()),
        portForwardController: PortForwardController(
          getIt<PortForwardRepository>(),
          getIt<PortForwardService>(),
        ),
      ),
    );

    await getIt.allReady();
    getIt<PortForwardRepository>().setAllDisabled();

    return ServerContainer._(
      getIt: getIt,
      databaseService: getIt<DatabaseService>(),
      portForwardService: getIt<PortForwardService>(),
      dockerSocketTunnelService: getIt<DockerSocketTunnelService>(),
      accessService: getIt<AccessAuthService>(),
      operationLogService: getIt<OperationLogService>(),
      portForwardRepository: getIt<PortForwardRepository>(),
      serverRepository: getIt<ServerRepository>(),
      apiRoutes: getIt<ApiRoutes>(),
    );
  }

  Future<void> dispose() async {
    await dockerSocketTunnelService.stopAll();
    await portForwardService.stopAll();
    databaseService.close();
    await _getIt.reset(dispose: true);
  }
}
