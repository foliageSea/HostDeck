import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:host_deck/server/app/server_handlers.dart';
import 'package:host_deck/server/features/access/access_auth_service.dart';
import 'package:host_deck/server/features/code_server/code_server_models.dart';
import 'package:host_deck/server/features/code_server/code_server_proxy.dart';
import 'package:host_deck/server/features/code_server/code_server_proxy_middleware.dart';

void main() {
  late HttpServer upstream;
  late HttpServer proxy;
  late List<String> seenPaths;
  late HttpClient client;
  late CodeServerProxy proxyServer;
  late _FakeResolver resolver;

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

    resolver = _FakeResolver(CodeServerUpstream('127.0.0.1', upstream.port));
    proxyServer = CodeServerProxy(
      resolver: resolver,
      accessService: AccessAuthService(),
    );
    proxy = await shelf_io.serve(
      const Pipeline()
          .addMiddleware(accessLogMiddleware(Logger('ServerService')))
          .addMiddleware(codeServerProxyMiddleware(proxyServer))
          .addHandler((_) => Response.notFound('fallback')),
      '127.0.0.1',
      0,
    );
  });

  tearDown(() async {
    client.close(force: true);
    await proxyServer.dispose();
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

  test('logs IDE requests once under CodeServerProxy', () async {
    final previousLevel = Logger.root.level;
    Logger.root.level = Level.ALL;
    final records = <LogRecord>[];
    final subscription = Logger.root.onRecord.listen(records.add);
    try {
      for (final path in [
        '/ide/abc12345/hello?x=1',
        '/ide/abc12345/missing',
        '/ide',
      ]) {
        final response = await get(path);
        await response.drain<void>();
      }
      expect(records, hasLength(3));
      expect(
        records.map((record) => record.loggerName),
        everyElement('CodeServerProxy'),
      );
      expect(records.map((record) => record.level), everyElement(Level.FINE));
      expect(
        records.first.message,
        matches(r'^GET /ide/abc12345/hello 200 \d+ms \| x=1$'),
      );
      expect(records[1].message, contains('/ide/abc12345/missing 404 '));
      expect(records[2].message, contains('/ide 404 '));

      records.clear();
      final response = await get('/idea');
      await response.drain<void>();
      expect(records, hasLength(1));
      expect(records.single.loggerName, 'ServerService');
      expect(records.single.level, Level.WARNING);
    } finally {
      await subscription.cancel();
      Logger.root.level = previousLevel;
    }
  });

  test('logs unexpected IDE failures once and rethrows them', () async {
    final previousLevel = Logger.root.level;
    Logger.root.level = Level.ALL;
    final records = <LogRecord>[];
    final subscription = Logger.root.onRecord.listen(records.add);
    final error = StateError('resolver failed');
    resolver.error = error;
    try {
      final handler = accessLogMiddleware(Logger('ServerService'))(
        codeServerProxyMiddleware(proxyServer)(
          (_) => Response.notFound('fallback'),
        ),
      );
      await expectLater(
        handler(Request('GET', Uri.parse('http://localhost/ide/abc12345/'))),
        throwsA(same(error)),
      );
      expect(records, hasLength(1));
      expect(records.single.loggerName, 'CodeServerProxy');
      expect(records.single.level, Level.SEVERE);
      expect(records.single.message, contains('/ide/abc12345/ 500 '));
      expect(records.single.error, same(error));
      expect(records.single.stackTrace, isNotNull);
    } finally {
      await subscription.cancel();
      Logger.root.level = previousLevel;
    }
  });

  test('uses the custom logger for IDE access logs', () async {
    final previousLevel = Logger.root.level;
    Logger.root.level = Level.ALL;
    final records = <LogRecord>[];
    final subscription = Logger.root.onRecord.listen(records.add);
    final customProxy = CodeServerProxy(
      resolver: resolver,
      accessService: AccessAuthService(),
      log: Logger('custom-ide-proxy'),
    );
    try {
      final response = await customProxy.handle(
        Request('GET', Uri.parse('http://localhost/ide')),
      );
      expect(response.statusCode, 404);
      expect(records, hasLength(1));
      expect(records.single.loggerName, 'custom-ide-proxy');
    } finally {
      await customProxy.dispose();
      await subscription.cancel();
      Logger.root.level = previousLevel;
    }
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
  Object? error;

  _FakeResolver(this.upstream);

  @override
  Future<CodeServerUpstream?> resolve(String sessionId) async {
    if (error != null) throw error!;
    return sessionId == 'abc12345' ? upstream : null;
  }
}
