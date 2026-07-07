import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  if (args.isEmpty || args.contains('--help') || args.contains('-h')) {
    _printUsage();
    return;
  }

  final command = args.first;
  final parser = _ArgParser(args.skip(1).toList());
  final baseUrl = parser.option('hostdeck-url') ?? 'http://127.0.0.1:8080';

  try {
    final result = switch (command) {
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

Future<Map<String, dynamic>> _exec(String baseUrl, _ArgParser parser) async {
  final connectionId = parser.requiredOption('connection');
  final command = parser.commandText;
  if (command == null || command.isEmpty) {
    throw UsageException('Missing command text after --.');
  }

  return _post(baseUrl, '/api/agent/exec', {
    'connectionId': connectionId,
    'command': command,
    if (parser.option('cwd') case final cwd?) 'cwd': cwd,
    if (parser.optionInt('timeout-ms') case final timeoutMs?)
      'timeoutMs': timeoutMs,
    if (parser.optionInt('max-output-bytes') case final maxOutputBytes?)
      'maxOutputBytes': maxOutputBytes,
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
    if (parser.option('cwd') case final cwd?) 'cwd': cwd,
    if (parser.optionInt('timeout-ms') case final timeoutMs?)
      'timeoutMs': timeoutMs,
  });
}

Future<String> _readInput(_ArgParser parser) async {
  final file = parser.option('file');
  if (file != null) {
    return File(file).readAsString();
  }

  return stdin.transform(utf8.decoder).join();
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
  hostdeck exec --connection <id> [--cwd <path>] -- <command>
  hostdeck read --connection <id> --path <remote-path>
  hostdeck write --connection <id> --path <remote-path> [--file <local-file>]
  hostdeck patch --connection <id> [--cwd <path>] [--file <diff-file>]

Options:
  --hostdeck-url <url>       HostDeck server URL, default: http://127.0.0.1:8080
  --connection <id>          SSH connection id from HostDeck
  --cwd <path>               Remote working directory
  --path <path>              Remote file path
  --file <path>              Read write/patch content from local file; otherwise stdin
  --timeout-ms <ms>          Command timeout, default: 60000
  --max-output-bytes <n>     Exec stdout/stderr limit, default: 524288

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
