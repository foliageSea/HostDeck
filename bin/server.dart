import 'dart:io';
import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:host_deck/server/app/server_cli.dart';
import 'package:host_deck/server/app/server_lifecycle.dart';
import 'package:host_deck/server/app/server_logging.dart';
import 'package:host_deck/server/app/server_runtime.dart';
import 'package:host_deck/server/app/server_service.dart';
import 'package:host_deck/server/features/port_forwards/chrome_launcher.dart';
import 'package:host_deck/utils/app_settings.dart';
import 'package:host_deck/utils/runtime_paths.dart';

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
  final chromeLauncher = config.enableSecureBrowser
      ? ChromeLauncher(
          dataDirectory: await RuntimePaths.resolveDataDirectory(
            overridePath: config.dataDir,
          ),
          executablePath: config.chromePath,
        )
      : null;

  final server = ServerService(
    host: config.host,
    port: config.port,
    webDir: config.webDir,
    dataDir: config.dataDir,
    logDir: logging.isFileLoggingEnabled ? logDirectory.path : null,
    flushLogs: logging.flush,
    adminPassword: Platform.environment['HOSTDECK_ACCESS_PASSWORD'],
    apiToken: Platform.environment['HOSTDECK_API_TOKEN'],
    totpSecret: Platform.environment['HOSTDECK_ACCESS_TOTP_SECRET'],
    secureCookies:
        Platform.environment['HOSTDECK_SECURE_COOKIES']?.toLowerCase() ==
        'true',
    logService: logging.logService,
    chromeLauncher: chromeLauncher,
    tlsEnabled: config.tlsEnabled,
    tlsCertificatePath: config.tlsCertificatePath,
    tlsPrivateKeyPath: config.tlsPrivateKeyPath,
  );

  final log = Logger('ServerEntrypoint');

  try {
    await server.start();
    if (config.readyFile != null) {
      final file = File(config.readyFile!);
      await file.parent.create(recursive: true);
      await file.create(exclusive: true);
      if (!Platform.isWindows) {
        final result = await Process.run('chmod', ['600', file.path]);
        if (result.exitCode != 0) {
          throw StateError('Cannot protect ready file.');
        }
      }
      await file.writeAsString(
        jsonEncode({
          'pid': pid,
          'baseUrl': '${server.scheme}://127.0.0.1:${server.listeningPort}',
          'certificatePem': server.tlsCertificatePem,
        }),
        flush: true,
      );
    }
    log.info(
      'HostDeck server started at ${server.scheme}://${config.host}:${server.listeningPort} (web: ${config.webDir ?? 'disabled'})',
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
