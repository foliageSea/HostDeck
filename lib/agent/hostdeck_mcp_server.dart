import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:host_deck/agent/hostdeck_agent_client.dart';

/// MCP (Model Context Protocol) server exposing the HostDeck agent API
/// to local agents over stdio using newline-delimited JSON-RPC 2.0.
///
/// Supported methods: initialize, ping, tools/list, tools/call.
/// Notifications (no `id`) are accepted and never answered.
class HostDeckMcpServer {
  static const String serverName = 'hostdeck-mcp';
  static const String serverVersion = '0.3.1';
  static const String protocolVersion = '2025-06-18';

  static const int _errorParse = -32700;
  static const int _errorInvalidRequest = -32600;
  static const int _errorMethodNotFound = -32601;

  final HostDeckAgentClient _client;

  HostDeckMcpServer({HostDeckAgentClient? client})
    : _client = client ?? HostDeckAgentClient();

  /// Runs the server loop: reads JSON-RPC messages from [input] line by line
  /// and writes responses to [output]. Returns when the input stream closes.
  Future<void> run({Stream<List<int>>? input, IOSink? output}) async {
    final inStream = input ?? stdin;
    final outSink = output ?? stdout;

    await for (final line
        in inStream.transform(utf8.decoder).transform(const LineSplitter())) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        continue;
      }

      Object? decoded;
      try {
        decoded = jsonDecode(trimmed);
      } catch (_) {
        _write(outSink, _error(null, _errorParse, 'Parse error'));
        continue;
      }

      if (decoded is! Map<String, dynamic>) {
        _write(outSink, _error(null, _errorInvalidRequest, 'Invalid request'));
        continue;
      }

      final response = await handleMessage(decoded);
      if (response != null) {
        _write(outSink, response);
      }
    }

    await outSink.flush();
  }

  void _write(IOSink out, Map<String, dynamic> message) {
    out.writeln(jsonEncode(message));
  }

  /// Handles a single decoded JSON-RPC message. Returns the response object,
  /// or null when the message is a notification that must not be answered.
  Future<Map<String, dynamic>?> handleMessage(
    Map<String, dynamic> message,
  ) async {
    final id = message['id'];
    final method = message['method'];
    if (method is! String || method.isEmpty) {
      if (id == null) {
        return null; // Not a request we can answer.
      }
      return _error(id, _errorInvalidRequest, 'Missing method');
    }

    final isNotification = !message.containsKey('id');

    switch (method) {
      case 'initialize':
        if (isNotification) return null;
        return _result(id, _initializeResult());
      case 'ping':
        if (isNotification) return null;
        return _result(id, const <String, dynamic>{});
      case 'tools/list':
        if (isNotification) return null;
        return _result(id, {'tools': toolDefinitions()});
      case 'tools/call':
        if (isNotification) return null;
        return _result(id, await _callTool(message['params']));
      case 'notifications/initialized':
      case 'notifications/cancelled':
        return null;
      default:
        if (isNotification) return null;
        return _error(id, _errorMethodNotFound, 'Method not found: $method');
    }
  }

  Map<String, dynamic> _initializeResult() {
    return {
      'protocolVersion': protocolVersion,
      'capabilities': {
        'tools': {'listChanged': false},
      },
      'serverInfo': {'name': serverName, 'version': serverVersion},
      'instructions':
          'HostDeck agent bridge. Use hostdeck_sessions to find '
          'connectionId values, then hostdeck_exec / hostdeck_read_file / '
          'hostdeck_write_file / hostdeck_apply_patch to work on the remote '
          'host through the running HostDeck server.',
    };
  }

  Future<Map<String, dynamic>> _callTool(Object? params) async {
    if (params is! Map<String, dynamic>) {
      throw _McpCallException('tools/call requires params');
    }
    final name = params['name'];
    if (name is! String || name.isEmpty) {
      throw _McpCallException('tools/call requires a tool name');
    }
    final arguments = params['arguments'];
    final args = arguments is Map<String, dynamic>
        ? arguments
        : const <String, dynamic>{};

    try {
      final result = switch (name) {
        'hostdeck_discover' => await _client.discover(),
        'hostdeck_sessions' => await _client.listSessions(),
        'hostdeck_exec' => await _execTool(args),
        'hostdeck_read_file' => await _readTool(args),
        'hostdeck_write_file' => await _writeTool(args),
        'hostdeck_apply_patch' => await _patchTool(args),
        _ => throw _McpCallException('Unknown tool: $name'),
      };
      return _toolResult(result);
    } on _McpCallException catch (e) {
      return _toolResult({
        'code': 400,
        'message': e.message,
        'data': null,
      }, isError: true);
    } catch (e) {
      return _toolResult({
        'code': 500,
        'message': e.toString(),
        'data': null,
      }, isError: true);
    }
  }

  Map<String, dynamic> _toolResult(
    Map<String, dynamic> result, {
    bool? isError,
  }) {
    final code = result['code'];
    final failed = isError ?? (code is int && code != 200);
    return {
      'content': [
        {'type': 'text', 'text': jsonEncode(result)},
      ],
      'isError': failed,
    };
  }

  Future<Map<String, dynamic>> _execTool(Map<String, dynamic> args) {
    return _client.exec(
      connectionId: _requiredString(args, 'connectionId'),
      command: _requiredString(args, 'command'),
      cwd: _optionalString(args, 'cwd'),
      timeoutMs: _optionalInt(args, 'timeoutMs'),
      maxOutputBytes: _optionalInt(args, 'maxOutputBytes'),
    );
  }

  Future<Map<String, dynamic>> _readTool(Map<String, dynamic> args) {
    return _client.readFile(
      connectionId: _requiredString(args, 'connectionId'),
      path: _requiredString(args, 'path'),
    );
  }

  Future<Map<String, dynamic>> _writeTool(Map<String, dynamic> args) {
    return _client.writeFile(
      connectionId: _requiredString(args, 'connectionId'),
      path: _requiredString(args, 'path'),
      content: _requiredString(args, 'content', allowEmpty: true),
    );
  }

  Future<Map<String, dynamic>> _patchTool(Map<String, dynamic> args) {
    return _client.applyPatch(
      connectionId: _requiredString(args, 'connectionId'),
      patch: _requiredString(args, 'patch'),
      cwd: _optionalString(args, 'cwd'),
      timeoutMs: _optionalInt(args, 'timeoutMs'),
    );
  }

  String _requiredString(
    Map<String, dynamic> args,
    String key, {
    bool allowEmpty = false,
  }) {
    final value = args[key];
    if (value is String && (allowEmpty || value.isNotEmpty)) {
      return value;
    }
    throw _McpCallException('Missing required argument: $key');
  }

  String? _optionalString(Map<String, dynamic> args, String key) {
    final value = args[key];
    if (value is String && value.isNotEmpty) {
      return value;
    }
    return null;
  }

  int? _optionalInt(Map<String, dynamic> args, String key) {
    final value = args[key];
    if (value is int) {
      return value;
    }
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }

  Map<String, dynamic> _result(Object? id, Object? result) => {
    'jsonrpc': '2.0',
    'id': ?id,
    'result': result,
  };

  Map<String, dynamic> _error(Object? id, int code, String message) => {
    'jsonrpc': '2.0',
    'id': id,
    'error': {'code': code, 'message': message},
  };

  /// Tool schemas advertised via tools/list.
  List<Map<String, dynamic>> toolDefinitions() {
    const connectionIdProp = {
      'type': 'string',
      'description':
          'SSH connection id managed by HostDeck; get valid values from '
          'hostdeck_sessions.',
    };
    const cwdProp = {
      'type': 'string',
      'description': 'Remote working directory for the command.',
    };
    const timeoutProp = {
      'type': 'integer',
      'description': 'Command timeout in milliseconds, default: 60000.',
    };

    return [
      {
        'name': 'hostdeck_discover',
        'description':
            'Resolve and probe the HostDeck server this bridge will use. '
            'Reports baseUrl, discovery source and agent API probe result.',
        'inputSchema': {'type': 'object', 'properties': <String, dynamic>{}},
      },
      {
        'name': 'hostdeck_sessions',
        'description':
            'List SSH connections and sessions currently maintained by the '
            'HostDeck server, including connectionId values for other tools.',
        'inputSchema': {'type': 'object', 'properties': <String, dynamic>{}},
      },
      {
        'name': 'hostdeck_exec',
        'description':
            'Execute a shell command on a remote host via HostDeck. Check '
            'data.exitCode for the remote exit status and data.truncated '
            'before trusting complete stdout/stderr.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'connectionId': connectionIdProp,
            'command': {
              'type': 'string',
              'description': 'Shell command to execute on the remote host.',
            },
            'cwd': cwdProp,
            'timeoutMs': timeoutProp,
            'maxOutputBytes': {
              'type': 'integer',
              'description':
                  'Per-stream stdout/stderr limit in bytes, default: 524288.',
            },
          },
          'required': ['connectionId', 'command'],
        },
      },
      {
        'name': 'hostdeck_read_file',
        'description': 'Read a UTF-8 text file from the remote host.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'connectionId': connectionIdProp,
            'path': {
              'type': 'string',
              'description': 'Absolute path of the remote file to read.',
            },
          },
          'required': ['connectionId', 'path'],
        },
      },
      {
        'name': 'hostdeck_write_file',
        'description':
            'Write (replace) a UTF-8 text file on the remote host with the '
            'given content.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'connectionId': connectionIdProp,
            'path': {
              'type': 'string',
              'description': 'Absolute path of the remote file to write.',
            },
            'content': {
              'type': 'string',
              'description': 'Full new text content of the file.',
            },
          },
          'required': ['connectionId', 'path', 'content'],
        },
      },
      {
        'name': 'hostdeck_apply_patch',
        'description':
            'Apply a unified diff on the remote host: runs git apply '
            '--check - first, then git apply - in the given cwd. Requires '
            'the remote cwd to be a git repository with git installed.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'connectionId': connectionIdProp,
            'patch': {
              'type': 'string',
              'description': 'Unified diff content to apply.',
            },
            'cwd': cwdProp,
            'timeoutMs': timeoutProp,
          },
          'required': ['connectionId', 'patch'],
        },
      },
    ];
  }
}

class _McpCallException implements Exception {
  final String message;

  const _McpCallException(this.message);
}
