import 'dart:async';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:host_deck/server/server_service.dart';
import 'package:host_deck/utils/app_settings.dart';

Future<void> main(List<String> args) async {
  _configureLogging();

  final config = _parseArgs(args);
  AppSettings.configure(dataDir: config.dataDir);

  final server = ServerService(
    host: config.host,
    port: config.port,
    webDir: config.webDir,
    dataDir: config.dataDir,
  );

  final log = Logger('ServerEntrypoint');

  try {
    await server.start();
    log.info(
      'HostDeck server started at http://${config.host}:${config.port} (web: ${config.webDir ?? 'disabled'})',
    );
  } catch (e, st) {
    log.severe('Failed to start server: $e', e, st);
    exit(1);
  }

  final stopSignals = <ProcessSignal>[ProcessSignal.sigint];
  if (!Platform.isWindows) {
    stopSignals.add(ProcessSignal.sigterm);
  }

  final subscriptions = <StreamSubscription<ProcessSignal>>[];
  for (final signal in stopSignals) {
    try {
      subscriptions.add(
        signal.watch().listen((_) async {
          log.info('Received ${signal.name}, shutting down...');
          await server.stop();
          for (final sub in subscriptions) {
            await sub.cancel();
          }
          exit(0);
        }),
      );
    } on SignalException {
      log.warning('Signal ${signal.name} is not supported on this platform.');
    }
  }
}

void _configureLogging() {
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
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
  });
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

  return _ServerConfig(
    host: values['host'] ?? '0.0.0.0',
    port: port,
    webDir: webDir,
    dataDir: values['data-dir'],
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
  --host <value>       Bind host, default: 0.0.0.0
  --port <value>       Bind port, default: 8080
  --web-dir <path>     Static web root directory (e.g. host-deck-ui/dist)
  --data-dir <path>    Data directory for sqlite and settings
  --help               Show this help
''');
  exit(exitCode);
}

class _ServerConfig {
  final String host;
  final int port;
  final String? webDir;
  final String? dataDir;

  const _ServerConfig({
    required this.host,
    required this.port,
    required this.webDir,
    required this.dataDir,
  });
}
