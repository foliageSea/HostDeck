import 'dart:io';

import 'package:path/path.dart' as p;

class ServerConfig {
  final String host;
  final int port;
  final String? webDir;
  final String? dataDir;
  final String? logDir;
  final int logMaxDays;

  const ServerConfig({
    required this.host,
    required this.port,
    required this.webDir,
    required this.dataDir,
    required this.logDir,
    required this.logMaxDays,
  });
}

ServerConfig parseServerArgs(List<String> args) {
  final values = <String, String>{};

  for (var i = 0; i < args.length; i++) {
    final token = args[i];
    if (!token.startsWith('--')) {
      continue;
    }

    final key = token.substring(2);
    if (key == 'help' || key == 'h') {
      printServerUsageAndExit();
    }

    if (i + 1 >= args.length || args[i + 1].startsWith('--')) {
      stderr.writeln('Missing value for option --$key');
      printServerUsageAndExit(exitCode: 64);
    }

    values[key] = args[i + 1];
    i++;
  }

  final port = int.tryParse(values['port'] ?? '') ?? 8080;
  if (port <= 0 || port > 65535) {
    stderr.writeln('Invalid port: $port');
    printServerUsageAndExit(exitCode: 64);
  }

  final logMaxDaysValue = values['log-max-days'];
  final logMaxDays = logMaxDaysValue == null
      ? 30
      : int.tryParse(logMaxDaysValue);
  if (logMaxDays == null || logMaxDays <= 0) {
    stderr.writeln('Invalid log max days: ${logMaxDaysValue ?? ''}');
    printServerUsageAndExit(exitCode: 64);
  }

  return ServerConfig(
    host: values['host'] ?? '127.0.0.1',
    port: port,
    webDir: values['web-dir'] ?? resolveDefaultWebDir(),
    dataDir: values['data-dir'],
    logDir: values['log-dir'],
    logMaxDays: logMaxDays,
  );
}

String? resolveDefaultWebDir() {
  final executableDir = File(Platform.resolvedExecutable).parent;
  final candidate = Directory(p.join(executableDir.path, '..', 'web'));
  return candidate.existsSync() ? candidate.path : null;
}

Never printServerUsageAndExit({int exitCode = 0}) {
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
