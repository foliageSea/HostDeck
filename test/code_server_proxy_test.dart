import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:host_deck/server/features/access/access_auth_service.dart';
import 'package:host_deck/server/features/code_server/code_server_models.dart';
import 'package:host_deck/server/features/code_server/code_server_proxy.dart';
import 'package:host_deck/server/features/code_server/code_server_proxy_middleware.dart';

void main() {
  late HttpServer upstream;
  late HttpServer proxy;
  late List<String> seenPaths;
  late HttpClient client;

  setUp(() async {
    client = HttpClient();
    seenPaths = [];
    final echo = webSocketHandler((WebSocketChannel channel, String? _) {
      channel.stream.listen(channel.sink.add, onDone: channel.sink.close);
    });
    upstream = await shelf_io.serve(
      (Request request) async {
        seenPaths.add('/${request.url.path}');
        if (request.url.path.startsWith('proxy/5173/')) {
          final route = request.url.path.substring('proxy/5173/'.length);
          if (route == 'redirect') {
            return Response.found('/login?next=1');
          }
          final html =
              '<script type="module" src="/@vite/client"></script>'
              '<script type="module" src="/renderer/src/main.ts"></script>';
          if (route == 'gzip') {
            return Response.ok(
              gzip.encode(utf8.encode(html)),
              headers: {
                'content-type': 'text/html',
                'content-encoding': 'gzip',
                'etag': 'upstream-version',
              },
            );
          }
          if (route == 'binary') {
            return Response.ok(
              [0, 255, 1, 128],
              headers: {'content-type': 'image/png'},
            );
          }
          return Response.ok(html, headers: {'content-type': 'text/html'});
        }
        if (request.url.path == 'missing') {
          return Response.notFound('missing');
        }
        if (request.url.path == 'ws') {
          return echo(request);
        }
        if (request.url.path == 'echo') {
          final body = await request.readAsString();
          return Response.ok('echo:$body');
        }
        return Response.ok(
          'hello',
          headers: const {'content-type': 'text/plain'},
        );
      },
      '127.0.0.1',
      0,
    );

    final proxyServer = CodeServerProxy(
      resolver: _FakeResolver(CodeServerUpstream('127.0.0.1', upstream.port)),
      accessService: AccessAuthService(),
    );
    proxy = await shelf_io.serve(
      const Pipeline()
          .addMiddleware(codeServerProxyMiddleware(proxyServer))
          .addHandler((_) => Response.notFound('fallback')),
      '127.0.0.1',
      0,
    );
  });

  tearDown(() async {
    client.close(force: true);
    await proxy.close(force: true);
    await upstream.close(force: true);
  });

  Future<HttpClientResponse> get(String path) async {
    final request = await client.getUrl(
      Uri.parse('http://127.0.0.1:${proxy.port}$path'),
    );
    return request.close();
  }

  test('strips /ide/<session> prefix and forwards query', () async {
    final response = await get('/ide/abc12345/hello?x=1');
    expect(response.statusCode, 200);
    expect(await response.transform(utf8.decoder).join(), 'hello');
    expect(seenPaths.single, '/hello');
  });

  test('passes upstream 404 through instead of SPA fallback', () async {
    final response = await get('/ide/abc12345/missing');
    expect(response.statusCode, 404);
  });

  test('redirects /ide/<session> to trailing slash', () async {
    final request = await client.getUrl(
      Uri.parse('http://127.0.0.1:${proxy.port}/ide/abc12345'),
    );
    request.followRedirects = false;
    final response = await request.close();
    expect(response.statusCode, 301);
    expect(response.headers.value('location'), '/ide/abc12345/');
  });

  test(
    'rewrites forwarded Vite page resources without changing IDE responses',
    () async {
      final response = await get('/ide/abc12345/proxy/5173/');
      final html = await response.transform(utf8.decoder).join();
      expect(html, contains('src="/ide/abc12345/proxy/5173/@vite/client"'));
      expect(
        html,
        contains('src="/ide/abc12345/proxy/5173/renderer/src/main.ts"'),
      );
      expect(seenPaths.single, '/proxy/5173/');
    },
  );

  test('decompresses forwarded HTML and discards stale validators', () async {
    final response = await get('/ide/abc12345/proxy/5173/gzip');
    expect(response.headers.value('content-encoding'), isNull);
    expect(response.headers.value('etag'), isNull);
    expect(
      await response.transform(utf8.decoder).join(),
      contains('/ide/abc12345/proxy/5173/@vite/client'),
    );
  });

  test('keeps binary forwarded responses unchanged', () async {
    final response = await get('/ide/abc12345/proxy/5173/binary');
    expect(
      await response.fold<List<int>>(
        [],
        (bytes, chunk) => bytes..addAll(chunk),
      ),
      [0, 255, 1, 128],
    );
  });

  test('keeps forwarded redirects within the application prefix', () async {
    final request = await client.getUrl(
      Uri.parse(
        'http://127.0.0.1:${proxy.port}/ide/abc12345/proxy/5173/redirect',
      ),
    );
    request.followRedirects = false;
    final response = await request.close();
    expect(
      response.headers.value('location'),
      '/ide/abc12345/proxy/5173/login?next=1',
    );
  });

  test('forwards POST body', () async {
    final request = await client.postUrl(
      Uri.parse('http://127.0.0.1:${proxy.port}/ide/abc12345/echo'),
    );
    request.headers.contentType = ContentType.text;
    request.write('payload');
    final response = await request.close();
    expect(await response.transform(utf8.decoder).join(), 'echo:payload');
  });

  test('bridges websocket', () async {
    final channel = WebSocketChannel.connect(
      Uri.parse('ws://127.0.0.1:${proxy.port}/ide/abc12345/ws'),
    );
    await channel.ready.timeout(const Duration(seconds: 5));
    channel.sink.add('ping');
    final reply = await channel.stream.first.timeout(
      const Duration(seconds: 5),
    );
    expect(reply, 'ping');
    await channel.sink.close();
  });

  test('rejects when auth is enabled and no session', () async {
    final authedProxy = CodeServerProxy(
      resolver: _FakeResolver(CodeServerUpstream('127.0.0.1', upstream.port)),
      accessService: AccessAuthService(password: 'secret'),
    );
    final server = await shelf_io.serve(
      const Pipeline()
          .addMiddleware(codeServerProxyMiddleware(authedProxy))
          .addHandler((_) => Response.notFound('fallback')),
      '127.0.0.1',
      0,
    );
    try {
      final response = await (await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}/ide/abc12345/hello'),
      )).close();
      expect(response.statusCode, 401);
    } finally {
      await authedProxy.dispose();
      await server.close(force: true);
    }
  });
}

class _FakeResolver implements CodeServerUpstreamResolver {
  final CodeServerUpstream upstream;

  _FakeResolver(this.upstream);

  @override
  Future<CodeServerUpstream?> resolve(String sessionId) async =>
      sessionId == 'abc12345' ? upstream : null;
}
