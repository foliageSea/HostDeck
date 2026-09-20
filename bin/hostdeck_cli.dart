import 'dart:convert';
import 'dart:io';

import 'package:host_deck/agent/hostdeck_agent_client.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty || args.contains('--help') || args.contains('-h')) {
    _printUsage();
    return;
  }

  final command = args.first;
  final parser = _ArgParser(args.skip(1).toList());
  final client = HostDeckAgentClient(
    baseUrl: parser.option('hostdeck-url'),
    token: parser.option('token') ?? HostDeckAgentClient.tokenFromEnvironment(),
  );

  try {
    final result = switch (command) {
      'discover' => await client.discover(),
      'sessions' => await client.listSessions(),
      'exec' => await _exec(client, parser),
      'read' => await _read(client, parser),
      'write' => await _write(client, parser),
      'patch' => await _patch(client, parser),
      _ => throw UsageException('Unknown command: $command'),
    };

    stdout.writeln(jsonEncode(result));
    final code = result['code'];
    if (code is int && code != 200) {
      exitCode = 1;
    }
  } on UsageException catch (e) {
    stderr.writeln(e.message);
    _printUsage();
    exitCode = 64;
  } catch (e) {
    stdout.writeln(
      jsonEncode({'code': 500, 'message': e.toString(), 'data': null}),
    );
    exitCode = 1;
  }
}

Future<Map<String, dynamic>> _exec(
  HostDeckAgentClient client,
  _ArgParser parser,
) async {
  final command = parser.commandText;
  if (command == null || command.isEmpty) {
    throw UsageException('Missing command text after --.');
  }

  return client.exec(
    connectionId: parser.requiredOption('connection'),
    command: command,
    cwd: parser.option('cwd'),
    timeoutMs: parser.optionInt('timeout-ms'),
    maxOutputBytes: parser.optionInt('max-output-bytes'),
  );
}

Future<Map<String, dynamic>> _read(
  HostDeckAgentClient client,
  _ArgParser parser,
) {
  return client.readFile(
    connectionId: parser.requiredOption('connection'),
    path: parser.requiredOption('path'),
  );
}

Future<Map<String, dynamic>> _write(
  HostDeckAgentClient client,
  _ArgParser parser,
) async {
  final content = await _readInput(parser);
  return client.writeFile(
    connectionId: parser.requiredOption('connection'),
    path: parser.requiredOption('path'),
    content: content,
  );
}

Future<Map<String, dynamic>> _patch(
  HostDeckAgentClient client,
  _ArgParser parser,
) async {
  final patch = await _readInput(parser);
  return client.applyPatch(
    connectionId: parser.requiredOption('connection'),
    patch: patch,
    cwd: parser.option('cwd'),
    timeoutMs: parser.optionInt('timeout-ms'),
  );
}

Future<String> _readInput(_ArgParser parser) async {
  final file = parser.option('file');
  if (file != null) {
    return File(file).readAsString();
  }

  return stdin.transform(utf8.decoder).join();
}

void _printUsage() {
  stdout.writeln('''
HostDeck CLI

Usage:
  hostdeck_cli discover [--hostdeck-url <url>] [--token <token>]
  hostdeck_cli sessions [--hostdeck-url <url>] [--token <token>]
  hostdeck_cli exec --connection <id> [--cwd <path>] [--timeout-ms <ms>] [--max-output-bytes <n>] -- <command>
  hostdeck_cli read --connection <id> --path <remote-path>
  hostdeck_cli write --connection <id> --path <remote-path> [--file <local-file>]
  hostdeck_cli patch --connection <id> [--cwd <path>] [--timeout-ms <ms>] [--file <diff-file>]

Options:
  --hostdeck-url <url>       HostDeck server URL, default: http://127.0.0.1:8080
  --token <token>            API token, or use HOSTDECK_TOKEN
  --connection <id>          SSH connection id from HostDeck
  --cwd <path>               Remote working directory
  --path <path>              Remote file path
  --file <path>              Read write/patch content from local file; otherwise stdin
  --timeout-ms <ms>          Command timeout, default: 60000
  --max-output-bytes <n>     Exec stdout/stderr limit, default: 524288

Agent contract:
  - Put --hostdeck-url after the command, not before it.
  - HostDeck server must already be running; CLI auto-discovers ~/.config/host-deck/instance.json when --hostdeck-url is omitted.
  - HOSTDECK_URL overrides auto-discovery; HOSTDECK_DISCOVERY_FILE overrides the instance file path.
  - HOSTDECK_TOKEN supplies Bearer authentication when --token is omitted.
  - Output is JSON: {"code": <int>, "message": <string>, "data": ...}.
  - CLI exit code only reflects top-level code != 200 or local usage/runtime errors.
  - For exec, inspect data.exitCode for remote command success.
  - For exec, inspect data.truncated before trusting complete stdout/stderr.
  - For write/patch, content is read from --file when provided, otherwise stdin.
  - patch runs git apply --check - before git apply - in the remote cwd.

Examples:
  hostdeck_cli discover
  hostdeck_cli sessions --hostdeck-url http://127.0.0.1:8080
  hostdeck_cli exec --connection <id> --cwd /repo -- git status --short
  hostdeck_cli exec --connection <id> --cwd /repo --timeout-ms 120000 --max-output-bytes 1048576 -- npm test
  hostdeck_cli write --connection <id> --path /tmp/file.txt < local.txt
  hostdeck_cli patch --connection <id> --cwd /repo < fix.diff

Build:
  fvm dart build cli --target bin/hostdeck_cli.dart --output build/hostdeck-cli
''');
}

class _ArgParser {
  final Map<String, String> _options = {};
  String? commandText;

  _ArgParser(List<String> args) {
    for (var i = 0; i < args.length; i++) {
      final token = args[i];
      if (token == '--') {
        commandText = args.skip(i + 1).join(' ');
        break;
      }

      if (!token.startsWith('--')) {
        throw UsageException('Unexpected argument: $token');
      }

      final key = token.substring(2);
      if (i + 1 >= args.length || args[i + 1].startsWith('--')) {
        throw UsageException('Missing value for --$key');
      }

      _options[key] = args[i + 1];
      i++;
    }
  }

  String? option(String key) => _options[key];

  String requiredOption(String key) {
    final value = option(key);
    if (value == null || value.isEmpty) {
      throw UsageException('Missing --$key');
    }
    return value;
  }

  int? optionInt(String key) {
    final value = option(key);
    if (value == null) {
      return null;
    }

    final parsed = int.tryParse(value);
    if (parsed == null) {
      throw UsageException('Invalid integer for --$key: $value');
    }
    return parsed;
  }
}

class UsageException implements Exception {
  final String message;

  const UsageException(this.message);
}
