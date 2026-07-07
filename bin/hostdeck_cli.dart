import 'dart:convert';
import 'dart:io';

import 'package:host_deck/utils/hostdeck_discovery.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty || args.contains('--help') || args.contains('-h')) {
    _printUsage();
    return;
  }

  final command = args.first;
  final parser = _ArgParser(args.skip(1).toList());

  try {
    final discovery = await _resolveHostDeckUrl(parser);
    final baseUrl = discovery.baseUrl;
    final result = switch (command) {
      'discover' => await _discover(discovery),
      'sessions' => await _sessions(baseUrl),
      'exec' => await _exec(baseUrl, parser),
      'read' => await _read(baseUrl, parser),
      'write' => await _write(baseUrl, parser),
      'patch' => await _patch(baseUrl, parser),
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

Future<Map<String, dynamic>> _discover(_DiscoveryResult discovery) async {
  final probe = await _probe(discovery.baseUrl);
  return {
    'code': probe.ok ? 200 : 503,
    'message': probe.ok ? 'success' : probe.message,
    'data': {
      'baseUrl': discovery.baseUrl,
      'source': discovery.source,
      'instanceFile': discovery.instanceFile,
      'probe': probe.data,
    },
  };
}

Future<Map<String, dynamic>> _sessions(String baseUrl) {
  return _get(baseUrl, '/api/agent/sessions');
}

Future<Map<String, dynamic>> _exec(String baseUrl, _ArgParser parser) async {
  final connectionId = parser.requiredOption('connection');
  final command = parser.commandText;
  if (command == null || command.isEmpty) {
    throw UsageException('Missing command text after --.');
  }

  return _post(baseUrl, '/api/agent/exec', {
    'connectionId': connectionId,
    'command': command,
    'cwd': ?parser.option('cwd'),
    'timeoutMs': ?parser.optionInt('timeout-ms'),
    'maxOutputBytes': ?parser.optionInt('max-output-bytes'),
  });
}

Future<Map<String, dynamic>> _read(String baseUrl, _ArgParser parser) {
  return _post(baseUrl, '/api/agent/file/read', {
    'connectionId': parser.requiredOption('connection'),
    'path': parser.requiredOption('path'),
  });
}

Future<Map<String, dynamic>> _write(String baseUrl, _ArgParser parser) async {
  final content = await _readInput(parser);
  return _post(baseUrl, '/api/agent/file/write', {
    'connectionId': parser.requiredOption('connection'),
    'path': parser.requiredOption('path'),
    'content': content,
  });
}

Future<Map<String, dynamic>> _patch(String baseUrl, _ArgParser parser) async {
  final patch = await _readInput(parser);
  return _post(baseUrl, '/api/agent/patch', {
    'connectionId': parser.requiredOption('connection'),
    'patch': patch,
    'cwd': ?parser.option('cwd'),
    'timeoutMs': ?parser.optionInt('timeout-ms'),
  });
}

Future<String> _readInput(_ArgParser parser) async {
  final file = parser.option('file');
  if (file != null) {
    return File(file).readAsString();
  }

  return stdin.transform(utf8.decoder).join();
}

Future<_DiscoveryResult> _resolveHostDeckUrl(_ArgParser parser) async {
  final explicitUrl = parser.option('hostdeck-url');
  if (explicitUrl != null && explicitUrl.isNotEmpty) {
    return _DiscoveryResult(baseUrl: explicitUrl, source: 'option');
  }

  final envUrl = Platform.environment[HostDeckDiscovery.envUrlKey]?.trim();
  if (envUrl != null && envUrl.isNotEmpty) {
    return _DiscoveryResult(baseUrl: envUrl, source: 'env');
  }

  final instanceFile = await HostDeckDiscovery.instanceFile();
  try {
    final instance = await HostDeckDiscovery.readInstance();
    final baseUrl = instance?['baseUrl'];
    if (baseUrl is String && baseUrl.isNotEmpty) {
      final probe = await _probe(baseUrl);
      if (probe.ok) {
        return _DiscoveryResult(
          baseUrl: baseUrl,
          source: 'instance-file',
          instanceFile: instanceFile.path,
        );
      }
    }
  } catch (_) {
    // Ignore stale or invalid discovery files and fall back to the default URL.
  }

  return _DiscoveryResult(
    baseUrl: 'http://127.0.0.1:8080',
    source: 'default',
    instanceFile: instanceFile.path,
  );
}

Future<_ProbeResult> _probe(String baseUrl) async {
  try {
    final result = await _get(baseUrl, '/api/agent/discovery');
    final data = result['data'];
    final ok =
        result['code'] == 200 &&
        data is Map &&
        data['name'] == 'HostDeck' &&
        data['agentApi'] == true;
    return _ProbeResult(
      ok: ok,
      message: ok ? 'success' : 'HostDeck discovery probe failed',
      data: result,
    );
  } catch (e) {
    return _ProbeResult(ok: false, message: e.toString(), data: null);
  }
}

Future<Map<String, dynamic>> _get(String baseUrl, String path) async {
  final client = HttpClient();
  try {
    final uri = Uri.parse(baseUrl).resolve(path);
    final request = await client.getUrl(uri);
    final response = await request.close();
    final text = await response.transform(utf8.decoder).join();
    final decoded = jsonDecode(text);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }

    return {
      'code': response.statusCode,
      'message': 'Invalid response',
      'data': text,
    };
  } finally {
    client.close(force: true);
  }
}

Future<Map<String, dynamic>> _post(
  String baseUrl,
  String path,
  Map<String, dynamic> body,
) async {
  final client = HttpClient();
  try {
    final uri = Uri.parse(baseUrl).resolve(path);
    final request = await client.postUrl(uri);
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(body));

    final response = await request.close();
    final text = await response.transform(utf8.decoder).join();
    final decoded = jsonDecode(text);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }

    return {
      'code': response.statusCode,
      'message': 'Invalid response',
      'data': text,
    };
  } finally {
    client.close(force: true);
  }
}

void _printUsage() {
  stdout.writeln('''
HostDeck CLI

Usage:
  hostdeck discover [--hostdeck-url <url>]
  hostdeck sessions [--hostdeck-url <url>]
  hostdeck exec --connection <id> [--cwd <path>] [--timeout-ms <ms>] [--max-output-bytes <n>] -- <command>
  hostdeck read --connection <id> --path <remote-path>
  hostdeck write --connection <id> --path <remote-path> [--file <local-file>]
  hostdeck patch --connection <id> [--cwd <path>] [--timeout-ms <ms>] [--file <diff-file>]

Options:
  --hostdeck-url <url>       HostDeck server URL, default: http://127.0.0.1:8080
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
  - Output is JSON: {"code": <int>, "message": <string>, "data": ...}.
  - CLI exit code only reflects top-level code != 200 or local usage/runtime errors.
  - For exec, inspect data.exitCode for remote command success.
  - For exec, inspect data.truncated before trusting complete stdout/stderr.
  - For write/patch, content is read from --file when provided, otherwise stdin.
  - patch runs git apply --check - before git apply - in the remote cwd.

Examples:
  hostdeck discover
  hostdeck sessions --hostdeck-url http://127.0.0.1:8080
  hostdeck exec --connection <id> --cwd /repo -- git status --short
  hostdeck exec --connection <id> --cwd /repo --timeout-ms 120000 --max-output-bytes 1048576 -- npm test
  hostdeck write --connection <id> --path /tmp/file.txt < local.txt
  hostdeck patch --connection <id> --cwd /repo < fix.diff

Build:
  fvm dart build cli --target bin/hostdeck_cli.dart --output build/hostdeck-cli
''');
}

class _DiscoveryResult {
  final String baseUrl;
  final String source;
  final String? instanceFile;

  const _DiscoveryResult({
    required this.baseUrl,
    required this.source,
    this.instanceFile,
  });
}

class _ProbeResult {
  final bool ok;
  final String message;
  final Object? data;

  const _ProbeResult({
    required this.ok,
    required this.message,
    required this.data,
  });
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
