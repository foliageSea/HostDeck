import 'dart:async';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:host_deck/server/app/server_service.dart';
import 'package:host_deck/utils/app_settings.dart';
import 'package:host_deck/utils/daily_file_logger.dart';
import 'package:host_deck/utils/runtime_paths.dart';

Future<void> main(List<String> args) async {
  final config = _parseArgs(args);
  final logDirectory = await _resolveLogDirectory(config);
  final logging = await _configureLogging(config, logDirectory);
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

  final stopSignals = <ProcessSignal>[ProcessSignal.sigint];
  if (!Platform.isWindows) {
    stopSignals.add(ProcessSignal.sigterm);
  }

  final subscriptions = <StreamSubscription<ProcessSignal>>[];
  var isStopping = false;
  for (final signal in stopSignals) {
    try {
      subscriptions.add(
        signal.watch().listen((_) async {
          if (isStopping) {
            return;
          }
          isStopping = true;
          log.info('Received ${signal.name}, shutting down...');
          await server.stop();
          for (final sub in subscriptions) {
            await sub.cancel();
          }
          await logging.close();
          exit(0);
        }),
      );
    } on SignalException {
      log.warning('Signal ${signal.name} is not supported on this platform.');
    }
  }
}

Future<Directory> _resolveLogDirectory(_ServerConfig config) async {
  if (config.logDir != null) {
    return Directory(config.logDir!);
  }

  final dataDirectory = await RuntimePaths.resolveDataDirectory(
    overridePath: config.dataDir,
  );
  return Directory(p.join(dataDirectory.path, 'logs'));
}

Future<_LoggingHandle> _configureLogging(
  _ServerConfig config,
  Directory logDirectory,
) async {
  Logger.root.level = Level.ALL;
  DailyFileLogger? fileLogger;
  try {
    fileLogger = DailyFileLogger(
      directory: logDirectory,
      maxDays: config.logMaxDays,
      onError: (error, stackTrace) {
        stderr.writeln('Failed to write log file: $error');
        stderr.writeln(stackTrace);
      },
    );
    await fileLogger.initialize();
  } catch (e, st) {
    stderr.writeln('Failed to initialize file logging: $e');
    stderr.writeln(st);
    fileLogger = null;
  }

  final subscription = Logger.root.onRecord.listen((record) {
    final ts = record.time.toIso8601String();
    final msg =
        '[$ts] [${record.level.name}] [${record.loggerName}] ${record.message}';
    stderr.writeln(msg);
    if (record.error != null) {
      stderr.writeln('Error: ${record.error}');
    }
    if (record.stackTrace != null) {
      stderr.writeln(record.stackTrace);
    }
    final details = StringBuffer(msg);
    if (record.error != null) {
      details.write('\nError: ${record.error}');
    }
    if (record.stackTrace != null) {
      details.write('\n${record.stackTrace}');
    }
    fileLogger?.write(details.toString());
  });
  return _LoggingHandle(subscription, fileLogger);
}

_ServerConfig _parseArgs(List<String> args) {
  final values = <String, String>{};

  for (var i = 0; i < args.length; i++) {
    final token = args[i];
    if (!token.startsWith('--')) {
      continue;
    }

    final key = token.substring(2);
    if (key == 'help' || key == 'h') {
      _printUsageAndExit();
    }

    if (i + 1 >= args.length || args[i + 1].startsWith('--')) {
      stderr.writeln('Missing value for option --$key');
      _printUsageAndExit(exitCode: 64);
    }

    values[key] = args[i + 1];
    i++;
  }

  final port = int.tryParse(values['port'] ?? '') ?? 8080;
  if (port <= 0 || port > 65535) {
    stderr.writeln('Invalid port: $port');
    _printUsageAndExit(exitCode: 64);
  }

  final webDir = values['web-dir'] ?? _resolveDefaultWebDir();
  final logMaxDaysValue = values['log-max-days'];
  final logMaxDays = logMaxDaysValue == null
      ? 30
      : int.tryParse(logMaxDaysValue);
  if (logMaxDays == null || logMaxDays <= 0) {
    stderr.writeln('Invalid log max days: ${logMaxDaysValue ?? ''}');
    _printUsageAndExit(exitCode: 64);
  }

  return _ServerConfig(
    host: values['host'] ?? '127.0.0.1',
    port: port,
    webDir: webDir,
    dataDir: values['data-dir'],
    logDir: values['log-dir'],
    logMaxDays: logMaxDays,
  );
}

String? _resolveDefaultWebDir() {
  final executableDir = File(Platform.resolvedExecutable).parent;
  final candidate = Directory(p.join(executableDir.path, '..', 'web'));
  if (candidate.existsSync()) {
    return candidate.path;
  }
  return null;
}

Never _printUsageAndExit({int exitCode = 0}) {
  stdout.writeln('''
HostDeck Server

Usage:
  dart run bin/server.dart [options]

Options:
  --host <value>       Bind host, default: 127.0.0.1
  --port <value>       Bind port, default: 8080
  --web-dir <path>     Static web root directory (e.g. host-deck-ui/dist)
  --data-dir <path>    Data directory for sqlite and settings
  --log-dir <path>     Log directory, default: <data-dir>/logs
  --log-max-days <n>   Days to retain log files, default: 30
  --help               Show this help

Environment:
  HOSTDECK_ACCESS_PASSWORD Enable browser password login
  HOSTDECK_API_TOKEN       Enable Bearer authentication for CLI/API clients
  HOSTDECK_SECURE_COOKIES  Set true when HTTPS terminates at a reverse proxy
''');
  exit(exitCode);
}

class _ServerConfig {
  final String host;
  final int port;
  final String? webDir;
  final String? dataDir;
  final String? logDir;
  final int logMaxDays;

  const _ServerConfig({
    required this.host,
    required this.port,
    required this.webDir,
    required this.dataDir,
    required this.logDir,
    required this.logMaxDays,
  });
}

class _LoggingHandle {
  final StreamSubscription<LogRecord> _subscription;
  final DailyFileLogger? _fileLogger;

  const _LoggingHandle(this._subscription, this._fileLogger);

  bool get isFileLoggingEnabled => _fileLogger != null;

  Future<void> flush() async {
    await _fileLogger?.flush();
  }

  Future<void> close() async {
    await _subscription.cancel();
    await _fileLogger?.close();
  }
}
