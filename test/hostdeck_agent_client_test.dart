import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:host_deck/agent/hostdeck_agent_client.dart';

void main() {
  late HttpServer backend;
  late List<Map<String, dynamic>> requests;

  Future<void> startBackend({
    bool agentApi = true,
    int sessionsCode = 200,
  }) async {
    requests = [];
    backend = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(
      backend.forEach((request) async {
        final body = await utf8.decoder.bind(request).join();
        requests.add({
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
                'agentApi': agentApi,
              },
            }),
          );
        } else if (request.uri.path == '/api/agent/sessions') {
          request.response.write(
            jsonEncode({
              'code': sessionsCode,
              'message': sessionsCode == 200 ? 'Success' : 'boom',
              'data': sessionsCode == 200 ? {'clients': <dynamic>[]} : null,
            }),
          );
        } else if (request.uri.path == '/api/agent/file/read') {
          request.response.write(
            jsonEncode({
              'code': 200,
              'message': 'Success',
              'data': {'path': '/tmp/a.txt', 'content': 'hello'},
            }),
          );
        } else if (request.uri.path == '/api/agent/patch') {
          request.response.write(
            jsonEncode({
              'code': 200,
              'message': 'Success',
              'data': {'checked': true, 'applied': true},
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

  tearDown(() async {
    await backend.close(force: true);
  });

  String baseUrl() => 'http://${backend.address.host}:${backend.port}';

  test('explicit baseUrl wins and probe validates the agent API', () async {
    await startBackend();
    final client = HostDeckAgentClient(baseUrl: baseUrl());

    final discovery = await client.resolveBaseUrl();
    expect(discovery.baseUrl, baseUrl());
    expect(discovery.source, 'option');

    final probe = await client.probe(baseUrl());
    expect(probe.ok, isTrue);
  });

  test('probe fails when the server is not a HostDeck agent API', () async {
    await startBackend(agentApi: false);
    final client = HostDeckAgentClient(baseUrl: baseUrl());

    final probe = await client.probe(baseUrl());
    expect(probe.ok, isFalse);
  });

  test('discover reports 503 when the endpoint cannot be probed', () async {
    await startBackend();
    final client = HostDeckAgentClient(baseUrl: 'http://127.0.0.1:1');

    final result = await client.discover();
    expect(result['code'], 503);
    expect((result['data'] as Map)['source'], 'option');
  });

  test('sends bearer token and serializes request bodies', () async {
    await startBackend();
    final client = HostDeckAgentClient(baseUrl: baseUrl(), token: ' t0k3n ');

    final read = await client.readFile(connectionId: 'c1', path: '/tmp/a.txt');
    expect(read['code'], 200);
    final readCall = requests.single;
    expect(readCall['authorization'], 'Bearer t0k3n');
    expect(readCall['body'], {'connectionId': 'c1', 'path': '/tmp/a.txt'});

    final patch = await client.applyPatch(
      connectionId: 'c1',
      patch: 'diff --git a/x b/x',
      cwd: '/repo',
      timeoutMs: 3000,
    );
    expect(patch['data']['applied'], isTrue);
    expect(requests.last['body'], {
      'connectionId': 'c1',
      'patch': 'diff --git a/x b/x',
      'cwd': '/repo',
      'timeoutMs': 3000,
    });
  });

  test('omits optional fields when they are not provided', () async {
    await startBackend();
    final client = HostDeckAgentClient(baseUrl: baseUrl());

    await client.exec(connectionId: 'c1', command: 'ls');
    final call = requests.singleWhere((r) => r['path'] == '/api/agent/exec');
    // exec endpoint not stubbed -> 404 body, but request shape is what matters.
    expect(call['body'], {'connectionId': 'c1', 'command': 'ls'});
  });

  test('business errors pass through with their code', () async {
    await startBackend(sessionsCode: 500);
    final client = HostDeckAgentClient(baseUrl: baseUrl());

    final result = await client.listSessions();
    expect(result['code'], 500);
    expect(result['message'], 'boom');
  });
}
