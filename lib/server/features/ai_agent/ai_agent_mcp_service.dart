import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:langchain/langchain.dart';

import 'package:host_deck/server/core/database/database_service.dart';
import 'package:host_deck/server/features/ai_agent/ai_agent_secret_store.dart';
import 'package:host_deck/server/features/ai_agent/ai_agent_tool_service.dart';
import 'package:host_deck/server/features/operation_logs/operation_log_service.dart';

class AiAgentMcpServer {
  final int id;
  final String name;
  final String url;
  final Map<String, String> headers;
  final bool enabled;

  const AiAgentMcpServer({
    required this.id,
    required this.name,
    required this.url,
    required this.headers,
    required this.enabled,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'url': url,
    'enabled': enabled,
    'hasHeaders': headers.isNotEmpty,
  };
}

class AiAgentMcpRepository {
  final DatabaseService _database;
  final AiAgentSecretStore _secretStore;

  AiAgentMcpRepository(this._database, this._secretStore);

  List<AiAgentMcpServer> list({bool enabledOnly = false}) {
    final rows = _database.db.select(
      '''SELECT id, name, url, encryptedHeaders, enabled
         FROM ai_agent_mcp_servers
         ${enabledOnly ? 'WHERE enabled = 1' : ''}
         ORDER BY name COLLATE NOCASE, id''',
    );
    return rows.map(_fromRow).toList(growable: false);
  }

  AiAgentMcpServer? get(int id) {
    final rows = _database.db.select(
      '''SELECT id, name, url, encryptedHeaders, enabled
         FROM ai_agent_mcp_servers WHERE id = ?''',
      [id],
    );
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  AiAgentMcpServer create({
    required String name,
    required String url,
    required Map<String, String> headers,
    required bool enabled,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    _database.db.execute(
      '''INSERT INTO ai_agent_mcp_servers
         (name, url, encryptedHeaders, enabled, createdAt, updatedAt)
         VALUES (?, ?, ?, ?, ?, ?)''',
      [name, url, _encryptHeaders(headers), enabled ? 1 : 0, now, now],
    );
    return get(_database.db.lastInsertRowId)!;
  }

  AiAgentMcpServer? update(
    int id, {
    required String name,
    required String url,
    Map<String, String>? headers,
    required bool enabled,
    required bool clearHeaders,
  }) {
    final existing = get(id);
    if (existing == null) return null;
    final nextHeaders = clearHeaders
        ? const <String, String>{}
        : headers ?? existing.headers;
    _database.db.execute(
      '''UPDATE ai_agent_mcp_servers
         SET name = ?, url = ?, encryptedHeaders = ?, enabled = ?, updatedAt = ?
         WHERE id = ?''',
      [
        name,
        url,
        _encryptHeaders(nextHeaders),
        enabled ? 1 : 0,
        DateTime.now().millisecondsSinceEpoch,
        id,
      ],
    );
    return get(id);
  }

  bool delete(int id) {
    _database.db.execute('DELETE FROM ai_agent_mcp_servers WHERE id = ?', [id]);
    return _database.db.updatedRows > 0;
  }

  AiAgentMcpServer _fromRow(dynamic row) {
    final encrypted = row['encryptedHeaders'] as String?;
    var headers = const <String, String>{};
    if (encrypted != null && encrypted.isNotEmpty) {
      final decoded = jsonDecode(_secretStore.decrypt(encrypted));
      if (decoded is Map<String, dynamic>) {
        headers = decoded.map((key, value) => MapEntry(key, value as String));
      }
    }
    return AiAgentMcpServer(
      id: row['id'] as int,
      name: row['name'] as String,
      url: row['url'] as String,
      headers: Map.unmodifiable(headers),
      enabled: (row['enabled'] as int) == 1,
    );
  }

  String? _encryptHeaders(Map<String, String> headers) =>
      headers.isEmpty ? null : _secretStore.encrypt(jsonEncode(headers));
}

class AiAgentMcpClient {
  static const protocolVersion = '2025-06-18';
  static const timeout = Duration(seconds: 20);
  static const maxResponseBytes = 1024 * 1024;
  static const maxToolOutputBytes = 64 * 1024;

  Future<List<AiAgentMcpTool>> listTools(AiAgentMcpServer server) async {
    final session = await _initialize(server);
    try {
      final discovered = <AiAgentMcpTool>[];
      String? cursor;
      do {
        final result = await _request(session, 'tools/list', {
          'cursor': ?cursor,
        });
        final tools = result['tools'];
        if (tools is! List) {
          throw const FormatException('MCP tools/list returned invalid tools.');
        }
        discovered.addAll(tools.map(AiAgentMcpTool.fromJson));
        final nextCursor = result['nextCursor'];
        cursor = nextCursor is String && nextCursor.isNotEmpty
            ? nextCursor
            : null;
      } while (cursor != null && discovered.length < 256);
      if (discovered.length > 256) {
        return List.unmodifiable(discovered.take(256));
      }
      return List.unmodifiable(discovered);
    } finally {
      session.client.close(force: true);
    }
  }

  Future<AiAgentToolResult> callTool(
    AiAgentMcpServer server,
    String name,
    Map<String, dynamic> arguments,
  ) async {
    final session = await _initialize(server);
    try {
      final result = await _request(session, 'tools/call', {
        'name': name,
        'arguments': arguments,
      });
      final isError = result['isError'] == true;
      final rawContent = _toolContent(result);
      final content = _limitToolOutput(rawContent);
      return AiAgentToolResult(
        success: !isError,
        content: content,
        summary: '${server.name}: $name ${isError ? 'failed' : 'completed'}',
        details: {
          'mcpServer': server.name,
          'mcpTool': name,
          'truncated': content.length < rawContent.length,
          if (result['structuredContent'] != null)
            'structured': result['structuredContent'],
        },
      );
    } finally {
      session.client.close(force: true);
    }
  }

  Future<_McpSession> _initialize(AiAgentMcpServer server) async {
    final uri = Uri.parse(server.url);
    final client = HttpClient()..connectionTimeout = timeout;
    final session = _McpSession(client: client, server: server, uri: uri);
    try {
      final result = await _request(session, 'initialize', {
        'protocolVersion': protocolVersion,
        'capabilities': const <String, dynamic>{},
        'clientInfo': const {'name': 'HostDeck', 'version': '0.3.1'},
      });
      final negotiated = result['protocolVersion'];
      if (negotiated is String && negotiated.isNotEmpty) {
        session.protocolVersion = negotiated;
      }
      await _notification(session, 'notifications/initialized');
      return session;
    } catch (_) {
      client.close(force: true);
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _request(
    _McpSession session,
    String method,
    Map<String, dynamic> params,
  ) async {
    final id = session.nextId++;
    final response = await _post(session, {
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': params,
    });
    final message = _decodeResponse(response.body, id);
    final error = message['error'];
    if (error is Map) {
      throw StateError(error['message']?.toString() ?? 'MCP request failed.');
    }
    final result = message['result'];
    if (result is! Map<String, dynamic>) {
      throw const FormatException('MCP response is missing a result.');
    }
    return result;
  }

  Future<void> _notification(_McpSession session, String method) async {
    await _post(session, {'jsonrpc': '2.0', 'method': method});
  }

  Future<_McpHttpResponse> _post(
    _McpSession session,
    Map<String, dynamic> payload,
  ) async {
    final request = await session.client.postUrl(session.uri).timeout(timeout);
    request.headers
      ..set(HttpHeaders.acceptHeader, 'application/json, text/event-stream')
      ..set(HttpHeaders.contentTypeHeader, 'application/json')
      ..set('MCP-Protocol-Version', session.protocolVersion);
    if (session.sessionId != null) {
      request.headers.set('MCP-Session-Id', session.sessionId!);
    }
    for (final entry in session.server.headers.entries) {
      request.headers.set(entry.key, entry.value);
    }
    request.write(jsonEncode(payload));
    final response = await request.close().timeout(timeout);
    final sessionId = response.headers.value('MCP-Session-Id');
    if (sessionId != null && sessionId.isNotEmpty) {
      session.sessionId = sessionId;
    }
    final body = await _readBounded(response).timeout(timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'MCP server returned HTTP ${response.statusCode}.',
        uri: session.uri,
      );
    }
    return _McpHttpResponse(body);
  }

  Future<String> _readBounded(HttpClientResponse response) async {
    final bytes = <int>[];
    await for (final chunk in response) {
      bytes.addAll(chunk);
      if (bytes.length > maxResponseBytes) {
        throw const FormatException('MCP response is too large.');
      }
    }
    return utf8.decode(bytes);
  }

  Map<String, dynamic> _decodeResponse(String body, int id) {
    for (final candidate in _responseCandidates(body)) {
      final decoded = jsonDecode(candidate);
      if (decoded is Map<String, dynamic> && decoded['id'] == id) {
        return decoded;
      }
    }
    throw const FormatException(
      'MCP server did not return the expected response.',
    );
  }

  Iterable<String> _responseCandidates(String body) sync* {
    final trimmed = body.trim();
    if (trimmed.startsWith('{')) {
      yield trimmed;
      return;
    }
    final data = <String>[];
    for (final line in const LineSplitter().convert(body)) {
      if (line.isEmpty) {
        if (data.isNotEmpty) {
          yield data.join('\n');
          data.clear();
        }
      } else if (line.startsWith('data:')) {
        data.add(line.substring(5).trimLeft());
      }
    }
    if (data.isNotEmpty) yield data.join('\n');
  }

  String _toolContent(Map<String, dynamic> result) {
    final values = <String>[];
    final content = result['content'];
    if (content is List) {
      for (final item in content) {
        if (item is Map && item['type'] == 'text' && item['text'] is String) {
          values.add(item['text'] as String);
        } else {
          values.add(jsonEncode(item));
        }
      }
    }
    if (result.containsKey('structuredContent')) {
      values.add(jsonEncode(result['structuredContent']));
    }
    return values.isEmpty ? '{}' : values.join('\n');
  }

  String _limitToolOutput(String value) {
    final bytes = utf8.encode(value);
    if (bytes.length <= maxToolOutputBytes) return value;
    return '${utf8.decode(bytes.take(maxToolOutputBytes).toList(), allowMalformed: true)}\n[truncated]';
  }
}

class AiAgentMcpToolService implements AiAgentToolExecutor {
  final AiAgentToolService _builtIn;
  final AiAgentMcpRepository _repository;
  final AiAgentMcpClient _client;
  final OperationLogService _operationLogs;
  Map<String, _RegisteredMcpTool> _tools = const {};

  AiAgentMcpToolService(
    this._builtIn,
    this._repository,
    this._client,
    this._operationLogs,
  );

  @override
  Future<List<ToolSpec>> resolveSpecs() async {
    final registered = <String, _RegisteredMcpTool>{};
    final specs = <ToolSpec>[...await _builtIn.resolveSpecs()];
    for (final server in _repository.list(enabledOnly: true)) {
      try {
        final tools = await _client.listTools(server);
        for (final tool in tools.take(64)) {
          var name = _toolName(server.id, tool.name);
          var suffix = 2;
          while (registered.containsKey(name)) {
            name = '${_toolName(server.id, tool.name)}_$suffix';
            suffix++;
          }
          registered[name] = _RegisteredMcpTool(server, tool);
          specs.add(
            ToolSpec(
              name: name,
              description: '[MCP: ${server.name}] ${tool.description}',
              inputJsonSchema: tool.inputSchema,
            ),
          );
        }
      } catch (_) {
        // A disconnected optional MCP server must not prevent the agent from running.
      }
    }
    _tools = Map.unmodifiable({..._tools, ...registered});
    return List.unmodifiable(specs);
  }

  @override
  bool requiresApproval(String name) =>
      _tools.containsKey(name) || _builtIn.requiresApproval(name);

  @override
  String summary(String name) {
    final registered = _tools[name];
    return registered == null
        ? _builtIn.summary(name)
        : '${registered.server.name}: ${registered.tool.name}';
  }

  @override
  Map<String, dynamic> normalizeArguments(
    String name,
    Map<String, dynamic> arguments,
  ) {
    if (_tools.containsKey(name)) return Map.unmodifiable(arguments);
    return _builtIn.normalizeArguments(name, arguments);
  }

  @override
  Future<AiAgentToolResult> execute({
    required String connectionId,
    required String targetKey,
    required String name,
    required Map<String, dynamic> arguments,
  }) async {
    final registered = _tools[name];
    if (registered == null) {
      return _builtIn.execute(
        connectionId: connectionId,
        targetKey: targetKey,
        name: name,
        arguments: arguments,
      );
    }
    try {
      final result = await _client.callTool(
        registered.server,
        registered.tool.name,
        arguments,
      );
      if (result.success) {
        _operationLogs.success(
          category: 'aiAgent',
          action: 'mcpToolCall',
          target: targetKey,
          connectionId: connectionId,
        );
      } else {
        _operationLogs.failure(
          category: 'aiAgent',
          action: 'mcpToolCall',
          target: targetKey,
          connectionId: connectionId,
          error: 'MCP tool returned an error',
        );
      }
      return result;
    } catch (_) {
      _operationLogs.failure(
        category: 'aiAgent',
        action: 'mcpToolCall',
        target: targetKey,
        connectionId: connectionId,
        error: 'MCP tool execution failed',
      );
      return AiAgentToolResult(
        success: false,
        content: 'MCP tool execution failed.',
        summary: '${registered.server.name}: ${registered.tool.name} failed',
      );
    }
  }

  String _toolName(int serverId, String name) {
    final slug = name.toLowerCase().replaceAll(RegExp('[^a-z0-9_-]+'), '_');
    final safe = slug.isEmpty ? 'tool' : slug;
    return 'mcp_${serverId}_${safe.substring(0, safe.length.clamp(0, 48))}';
  }
}

class AiAgentMcpTool {
  final String name;
  final String description;
  final Map<String, dynamic> inputSchema;

  const AiAgentMcpTool({
    required this.name,
    required this.description,
    required this.inputSchema,
  });

  factory AiAgentMcpTool.fromJson(Object? value) {
    if (value is! Map<String, dynamic> || value['name'] is! String) {
      throw const FormatException('MCP server returned an invalid tool.');
    }
    final schema = value['inputSchema'];
    return AiAgentMcpTool(
      name: value['name'] as String,
      description: value['description'] is String
          ? value['description'] as String
          : '',
      inputSchema: schema is Map<String, dynamic>
          ? schema
          : const {'type': 'object', 'properties': <String, dynamic>{}},
    );
  }
}

class _McpSession {
  final HttpClient client;
  final AiAgentMcpServer server;
  final Uri uri;
  int nextId = 1;
  String? sessionId;
  String protocolVersion = AiAgentMcpClient.protocolVersion;

  _McpSession({required this.client, required this.server, required this.uri});
}

class _McpHttpResponse {
  final String body;
  const _McpHttpResponse(this.body);
}

class _RegisteredMcpTool {
  final AiAgentMcpServer server;
  final AiAgentMcpTool tool;
  const _RegisteredMcpTool(this.server, this.tool);
}
