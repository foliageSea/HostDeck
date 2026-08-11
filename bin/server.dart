import 'dart:io';

import 'package:logging/logging.dart';
import 'package:host_deck/server/app/server_cli.dart';
import 'package:host_deck/server/app/server_lifecycle.dart';
import 'package:host_deck/server/app/server_logging.dart';
import 'package:host_deck/server/app/server_runtime.dart';
import 'package:host_deck/server/app/server_service.dart';
import 'package:host_deck/utils/app_settings.dart';

Future<void> main(List<String> args) async {
  final config = parseServerArgs(args);
  _printBanner(await resolveAppVersion());
  final logDirectory = await resolveServerLogDirectory(
    logDir: config.logDir,
    dataDir: config.dataDir,
  );
  final logging = await configureServerLogging(
    directory: logDirectory,
    maxDays: config.logMaxDays,
  );
  AppSettings.configure(dataDir: config.dataDir);

  final server = ServerService(
    host: config.host,
    port: config.port,
    webDir: config.webDir,
    dataDir: config.dataDir,
    logDir: logging.isFileLoggingEnabled ? logDirectory.path : null,
    flushLogs: logging.flush,
    adminPassword: Platform.environment['HOSTDECK_ACCESS_PASSWORD'],
    apiToken: Platform.environment['HOSTDECK_API_TOKEN'],
    secureCookies:
        Platform.environment['HOSTDECK_SECURE_COOKIES']?.toLowerCase() ==
        'true',
  );

  final log = Logger('ServerEntrypoint');

  try {
    await server.start();
    log.info(
      'HostDeck server started at http://${config.host}:${config.port} (web: ${config.webDir ?? 'disabled'})',
    );
  } catch (e, st) {
    log.severe('Failed to start server: $e', e, st);
    await logging.close();
    exit(1);
  }

  registerServerShutdownHandlers(
    log: log,
    stopServer: server.stop,
    closeLogging: logging.close,
  );
}

void _printBanner(String version) {
  stdout.writeln('''
  ██╗  ██╗ ██████╗ ███████╗████████╗██████╗ ███████╗ ██████╗██╗  ██╗
  ██║  ██║██╔═══██╗██╔════╝╚══██╔══╝██╔══██╗██╔════╝██╔════╝██║ ██╔╝
  ███████║██║   ██║███████╗   ██║   ██║  ██║█████╗  ██║     █████╔╝
  ██╔══██║██║   ██║╚════██║   ██║   ██║  ██║██╔══╝  ██║     ██╔═██╗
  ██║  ██║╚██████╔╝███████║   ██║   ██████╔╝███████╗╚██████╗██║  ██╗
  ╚═╝  ╚═╝ ╚═════╝ ╚══════╝   ╚═╝   ╚═════╝ ╚══════╝ ╚═════╝╚═╝  ╚═╝ v$version
''');
  stdout.flush();
}
