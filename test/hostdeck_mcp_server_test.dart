import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:host_deck/agent/hostdeck_agent_client.dart';
import 'package:host_deck/agent/hostdeck_mcp_server.dart';

void main() {
  group('protocol handling', () {
    late HostDeckMcpServer server;

    setUp(() {
      server = HostDeckMcpServer(
        client: HostDeckAgentClient(baseUrl: 'http://127.0.0.1:1'),
      );
    });

    test('initialize returns capabilities and server info', () async {
      final response = await server.handleMessage({
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'initialize',
        'params': {
          'protocolVersion': '2025-06-18',
          'capabilities': <String, dynamic>{},
          'clientInfo': {'name': 'test', 'version': '1'},
        },
      });

      expect(response, isNotNull);
      expect(response!['id'], 1);
      final result = response['result'] as Map<String, dynamic>;
      expect(result['protocolVersion'], HostDeckMcpServer.protocolVersion);
      expect(result['capabilities'], {
        'tools': {'listChanged': false},
      });
      expect(result['serverInfo'], {
        'name': HostDeckMcpServer.serverName,
        'version': HostDeckMcpServer.serverVersion,
      });
      expect(result['instructions'], contains('hostdeck_sessions'));
    });

    test('ping returns an empty result', () async {
      final response = await server.handleMessage({
        'jsonrpc': '2.0',
        'id': 'p1',
        'method': 'ping',
      });

      expect(response, {'jsonrpc': '2.0', 'id': 'p1', 'result': isEmpty});
    });

    test('tools/list advertises the six hostdeck tools with schemas', () async {
      final response = await server.handleMessage({
        'jsonrpc': '2.0',
        'id': 2,
        'method': 'tools/list',
      });

      final result = response!['result'] as Map<String, dynamic>;
      final tools = (result['tools'] as List).cast<Map<String, dynamic>>();
      expect(
        tools.map((tool) => tool['name']),
        containsAll([
          'hostdeck_discover',
          'hostdeck_sessions',
          'hostdeck_exec',
          'hostdeck_read_file',
          'hostdeck_write_file',
          'hostdeck_apply_patch',
        ]),
      );
      for (final tool in tools) {
        expect(
          tool['description'],
          isA<String>().having((d) => d.isNotEmpty, 'non-empty', isTrue),
        );
        final schema = tool['inputSchema'] as Map<String, dynamic>;
        expect(schema['type'], 'object');
      }

      final execTool = tools.singleWhere((t) => t['name'] == 'hostdeck_exec');
      expect(execTool['inputSchema']['required'], ['connectionId', 'command']);
    });

    test('notifications never produce a response', () async {
      for (final method in [
        'notifications/initialized',
        'notifications/cancelled',
        'initialize',
        'tools/list',
        'unknown_method',
      ]) {
        final response = await server.handleMessage({
          'jsonrpc': '2.0',
          'method': method,
        });
        expect(response, isNull, reason: '$method must not be answered');
      }
    });

    test('unknown method returns method-not-found error', () async {
      final response = await server.handleMessage({
        'jsonrpc': '2.0',
        'id': 3,
        'method': 'resources/list',
      });

      expect(response!['id'], 3);
      final error = response['error'] as Map<String, dynamic>;
      expect(error['code'], -32601);
      expect(error['message'], contains('resources/list'));
    });

    test('request without method returns invalid request', () async {
      final response = await server.handleMessage({'jsonrpc': '2.0', 'id': 4});
      final error = response!['error'] as Map<String, dynamic>;
      expect(error['code'], -32600);
    });

    test('tools/call with unknown tool reports an error result', () async {
      final response = await server.handleMessage({
        'jsonrpc': '2.0',
        'id': 5,
        'method': 'tools/call',
        'params': {'name': 'nope', 'arguments': <String, dynamic>{}},
      });

      final result = response!['result'] as Map<String, dynamic>;
      expect(result['isError'], isTrue);
      final content =
          (result['content'] as List).single as Map<String, dynamic>;
      final payload =
          jsonDecode(content['text'] as String) as Map<String, dynamic>;
      expect(payload['code'], 400);
      expect(payload['message'], contains('Unknown tool: nope'));
    });

    test('tools/call validates required arguments', () async {
      final response = await server.handleMessage({
        'jsonrpc': '2.0',
        'id': 6,
        'method': 'tools/call',
        'params': {
          'name': 'hostdeck_exec',
          'arguments': {'connectionId': 'c1'},
        },
      });

      final result = response!['result'] as Map<String, dynamic>;
      expect(result['isError'], isTrue);
      final content =
          (result['content'] as List).single as Map<String, dynamic>;
      final payload =
          jsonDecode(content['text'] as String) as Map<String, dynamic>;
      expect(payload['message'], contains('command'));
    });

    test(
      'tools/call failure to reach HostDeck becomes an error result',
      () async {
        // Port 1 is reserved/unreachable locally, so the HTTP call must fail.
        final response = await server.handleMessage({
          'jsonrpc': '2.0',
          'id': 7,
          'method': 'tools/call',
          'params': {
            'name': 'hostdeck_sessions',
            'arguments': <String, dynamic>{},
          },
        });

        final result = response!['result'] as Map<String, dynamic>;
        expect(result['isError'], isTrue);
        final content =
            (result['content'] as List).single as Map<String, dynamic>;
        final payload =
            jsonDecode(content['text'] as String) as Map<String, dynamic>;
        expect(payload['code'], 500);
      },
    );
  });

  group('end-to-end over stdio', () {
    late HttpServer backend;
    late List<Map<String, dynamic>> backendRequests;

    Future<void> startBackend() async {
      backendRequests = [];
      backend = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      unawaited(
        backend.forEach((request) async {
          final body = await utf8.decoder.bind(request).join();
          backendRequests.add({
            'method': request.method,
            'path': request.uri.path,
            'authorization': request.headers.value('authorization'),
            'body': body.isEmpty ? null : jsonDecode(body),
          });

          request.response.headers.contentType = ContentType.json;
          if (request.uri.path == '/api/agent/discovery') {
            request.response.write(
              jsonEncode({
                'code': 200,
                'message': 'Success',
                'data': {
                  'name': 'HostDeck',
                  'version': '0.3.1',
                  'agentApi': true,
                },
              }),
            );
          } else if (request.uri.path == '/api/agent/sessions') {
            request.response.write(
              jsonEncode({
                'code': 200,
                'message': 'Success',
                'data': {
                  'clients': [
                    {'connectionId': 'conn-1', 'host': 'example.com'},
                  ],
                },
              }),
            );
          } else if (request.uri.path == '/api/agent/exec') {
            request.response.write(
              jsonEncode({
                'code': 200,
                'message': 'Success',
                'data': {
                  'exitCode': 0,
                  'stdout': 'ok\n',
                  'stderr': '',
                  'truncated': false,
                },
              }),
            );
          } else {
            request.response.write(
              jsonEncode({'code': 404, 'message': 'not found', 'data': null}),
            );
          }
          await request.response.close();
        }),
      );
    }

    test('full MCP session: initialize -> tools/list -> tools/call', () async {
      await startBackend();
      addTearDown(() => backend.close(force: true));

      final baseUrl = 'http://${backend.address.host}:${backend.port}';
      final server = HostDeckMcpServer(
        client: HostDeckAgentClient(baseUrl: baseUrl, token: 'secret-token'),
      );

      final input = StreamController<List<int>>();
      final outputBuffer = StringBuffer();
      final output = IOSink(_StringBufferSink(outputBuffer));

      final runFuture = server.run(input: input.stream, output: output);

      final requests = [
        {
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'initialize',
          'params': {'protocolVersion': '2025-06-18'},
        },
        {'jsonrpc': '2.0', 'method': 'notifications/initialized'},
        {'jsonrpc': '2.0', 'id': 2, 'method': 'tools/list'},
        {
          'jsonrpc': '2.0',
          'id': 3,
          'method': 'tools/call',
          'params': {
            'name': 'hostdeck_sessions',
            'arguments': <String, dynamic>{},
          },
        },
        {
          'jsonrpc': '2.0',
          'id': 4,
          'method': 'tools/call',
          'params': {
            'name': 'hostdeck_exec',
            'arguments': {
              'connectionId': 'conn-1',
              'command': 'git status',
              'cwd': '/repo',
              'timeoutMs': 5000,
            },
          },
        },
        'this is not json',
      ];

      for (final request in requests) {
        input.add(
          utf8.encode(request is String ? request : jsonEncode(request)),
        );
        input.add(utf8.encode('\n'));
      }
      await input.close();
      await runFuture;

      final lines = outputBuffer
          .toString()
          .split('\n')
          .where((line) => line.trim().isNotEmpty)
          .map((line) => jsonDecode(line) as Map<String, dynamic>)
          .toList();

      // 4 requests with ids + 1 parse error; the notification gets no answer.
      expect(lines, hasLength(5));

      final byId = <Object?, Map<String, dynamic>>{
        for (final line in lines) line['id']: line,
      };
      expect(byId[1]!['result']['protocolVersion'], '2025-06-18');
      expect((byId[2]!['result']['tools'] as List), hasLength(6));

      final sessionsResult = byId[3]!['result'] as Map<String, dynamic>;
      expect(sessionsResult['isError'], isFalse);
      final sessionsPayload =
          jsonDecode(
                ((sessionsResult['content'] as List).single
                        as Map<String, dynamic>)['text']
                    as String,
              )
              as Map<String, dynamic>;
      expect(sessionsPayload['data']['clients'], hasLength(1));

      final execResult = byId[4]!['result'] as Map<String, dynamic>;
      expect(execResult['isError'], isFalse);
      final execPayload =
          jsonDecode(
                ((execResult['content'] as List).single
                        as Map<String, dynamic>)['text']
                    as String,
              )
              as Map<String, dynamic>;
      expect(execPayload['data']['exitCode'], 0);

      final parseError = lines.firstWhere((line) => line['error'] != null);
      expect(parseError['error']['code'], -32700);

      // Backend saw both API calls, each carrying the bearer token.
      expect(
        backendRequests.where((r) => r['path'] == '/api/agent/sessions'),
        hasLength(1),
      );
      final execCall = backendRequests.singleWhere(
        (r) => r['path'] == '/api/agent/exec',
      );
      expect(execCall['authorization'], 'Bearer secret-token');
      expect(execCall['body'], {
        'connectionId': 'conn-1',
        'command': 'git status',
        'cwd': '/repo',
        'timeoutMs': 5000,
      });
    });
  });
}

class _StringBufferSink implements StreamSink<List<int>> {
  final StringBuffer buffer;

  _StringBufferSink(this.buffer);

  @override
  Future<void> add(List<int> event) async {
    buffer.write(utf8.decode(event));
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final event in stream) {
      buffer.write(utf8.decode(event));
    }
  }

  @override
  Future<void> close() async {}

  @override
  Future<void> get done => Future.value();
}
