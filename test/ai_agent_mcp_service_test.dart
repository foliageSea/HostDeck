import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:host_deck/server/core/database/database_service.dart';
import 'package:host_deck/server/features/ai_agent/ai_agent_mcp_service.dart';
import 'package:host_deck/server/features/ai_agent/ai_agent_secret_store.dart';

void main() {
  late Directory dataDirectory;
  late DatabaseService database;
  late AiAgentMcpRepository repository;

  setUp(() async {
    dataDirectory = await Directory.systemTemp.createTemp('hostdeck-mcp-');
    database = DatabaseService(dataDir: dataDirectory.path);
    await database.init();
    final secretStore = AiAgentSecretStore(dataDir: dataDirectory.path);
    await secretStore.init();
    repository = AiAgentMcpRepository(database, secretStore);
  });

  tearDown(() async {
    database.close();
    await dataDirectory.delete(recursive: true);
  });

  test('stores MCP headers encrypted and never returns their values', () {
    final server = repository.create(
      name: 'Private tools',
      url: 'https://mcp.example.com/mcp',
      headers: const {'Authorization': 'Bearer secret-token'},
      enabled: true,
    );

    final stored =
        database.db
                .select('SELECT encryptedHeaders FROM ai_agent_mcp_servers')
                .single['encryptedHeaders']
            as String;

    expect(stored, isNot(contains('secret-token')));
    expect(server.toJson(), {
      'id': server.id,
      'name': 'Private tools',
      'url': 'https://mcp.example.com/mcp',
      'enabled': true,
      'hasHeaders': true,
    });
    expect(
      repository.get(server.id)!.headers['Authorization'],
      'Bearer secret-token',
    );
  });

  test('discovers and calls tools over Streamable HTTP', () async {
    final requests = <Map<String, dynamic>>[];
    final httpServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final serving = httpServer.forEach((request) async {
      expect(request.headers.value('authorization'), 'Bearer test');
      final payload =
          jsonDecode(await utf8.decoder.bind(request).join())
              as Map<String, dynamic>;
      requests.add(payload);
      final method = payload['method'];
      if (method == 'notifications/initialized') {
        expect(request.headers.value('mcp-session-id'), 'session-1');
        request.response.statusCode = HttpStatus.accepted;
      } else if (method == 'initialize') {
        request.response.headers.set('MCP-Session-Id', 'session-1');
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': payload['id'],
            'result': {
              'protocolVersion': AiAgentMcpClient.protocolVersion,
              'capabilities': {'tools': {}},
              'serverInfo': {'name': 'test', 'version': '1'},
            },
          }),
        );
      } else if (method == 'tools/list') {
        expect(request.headers.value('mcp-session-id'), 'session-1');
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': payload['id'],
            'result': {
              'tools': [
                {
                  'name': 'weather',
                  'description': 'Read weather',
                  'inputSchema': {
                    'type': 'object',
                    'properties': {
                      'city': {'type': 'string'},
                    },
                    'required': ['city'],
                  },
                },
              ],
            },
          }),
        );
      } else if (method == 'tools/call') {
        request.response.headers.contentType = ContentType(
          'text',
          'event-stream',
        );
        request.response.write(
          'event: message\n'
          'data: ${jsonEncode({
            'jsonrpc': '2.0',
            'id': payload['id'],
            'result': {
              'content': [
                {'type': 'text', 'text': 'Sunny'},
              ],
              'isError': false,
            },
          })}\n\n',
        );
      }
      await request.response.close();
    });

    final server = AiAgentMcpServer(
      id: 1,
      name: 'Weather',
      url: 'http://${httpServer.address.host}:${httpServer.port}/mcp',
      headers: const {'Authorization': 'Bearer test'},
      enabled: true,
    );
    final client = AiAgentMcpClient();
    try {
      final tools = await client.listTools(server);
      expect(tools.single.name, 'weather');
      expect(tools.single.inputSchema['type'], 'object');
      final cachedTools = await client.listTools(server);
      expect(cachedTools.single.name, 'weather');
      expect(
        requests.where((request) => request['method'] == 'tools/list'),
        hasLength(1),
      );

      await client.listTools(server, refresh: true);
      expect(
        requests.where((request) => request['method'] == 'tools/list'),
        hasLength(2),
      );

      final result = await client.callTool(server, 'weather', {
        'city': 'Shenzhen',
      });
      expect(result.success, isTrue);
      expect(result.content, 'Sunny');
      expect(
        requests.where((request) => request['method'] == 'initialize'),
        hasLength(3),
      );
    } finally {
      await httpServer.close(force: true);
      await serving;
    }
  });
}
