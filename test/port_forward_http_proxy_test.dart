import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:host_deck/server/core/http/path_http_proxy.dart';
import 'package:host_deck/server/core/ssh/ssh_service.dart';
import 'package:host_deck/server/features/access/access_auth_service.dart';
import 'package:host_deck/server/features/port_forwards/port_forward_http_proxy.dart';
import 'package:host_deck/server/features/port_forwards/port_forward_service.dart';

void main() {
  late HttpServer upstream;
  late HttpServer server;
  late HttpClient client;
  late PortForwardHttpProxy proxy;
  late _Resolver service;
  late Map<String, String> seenHeaders;
  late String seenPath;

  setUp(() async {
    client = HttpClient()..autoUncompress = false;
    seenHeaders = {};
    seenPath = '';
    final echo = webSocketHandler((WebSocketChannel channel, String? _) {
      channel.stream.listen(channel.sink.add, onDone: channel.sink.close);
    });
    upstream = await shelf_io.serve(
      (Request request) async {
        seenHeaders = request.headers;
        seenPath = request.url.toString();
        switch (request.url.path) {
          case 'missing':
            return Response.notFound('upstream missing');
          case 'redirect':
            return Response.found('/login?next=1');
          case 'cookies':
            return Response.ok(
              'cookies',
              headers: {
                'set-cookie': [
                  'sid=one; Path=/; HttpOnly; SameSite=Lax',
                  'theme=dark; Path=/settings; Domain=internal.test',
                  'hostdeck_session=overwrite; Path=/',
                ],
              },
            );
          case 'echo':
            return Response.ok(await request.readAsString());
          case 'ws':
            return echo(request);
          case 'binary':
            return Response.ok(
              [0, 255, 128],
              headers: {'content-type': 'image/png'},
            );
          case 'stream':
            return Response.ok(
              Stream.value(utf8.encode('data: hello\n\n')),
              headers: {'content-type': 'text/event-stream'},
            );
          default:
            return Response.ok(
              gzip.encode(utf8.encode('<script src="/app.js"></script>')),
              headers: {
                'content-type': 'text/html',
                'content-encoding': 'gzip',
                'etag': 'old',
              },
            );
        }
      },
      '127.0.0.1',
      0,
    );
    service = _Resolver(upstream.port);
    proxy = PortForwardHttpProxy(
      service: service,
      accessService: AccessAuthService(),
    );
    server = await shelf_io.serve(
      portForwardProxyMiddleware(proxy)((_) => Response.ok('SPA fallback')),
      '127.0.0.1',
      0,
    );
  });

  tearDown(() async {
    client.close(force: true);
    await proxy.dispose();
    await server.close(force: true);
    await upstream.close(force: true);
  });

  Uri url(String path) => Uri.parse('http://127.0.0.1:${server.port}$path');

  test(
    'maps encoded paths and query, rewrites gzip HTML and strips credentials',
    () async {
      final request = await client.getUrl(
        url('/port-forward/12/a%20b?q=a%2Fb'),
      );
      request.headers.set(
        'cookie',
        'hostdeck_session=secret; other=private; hdpf_12_sid=app; hdpf_13_sid=other',
      );
      request.headers.set('authorization', 'Bearer secret');
      final response = await request.close();
      expect(response.statusCode, 200);
      expect(seenPath, 'a%20b?q=a%2Fb');
      expect(seenHeaders['authorization'], isNull);
      expect(seenHeaders['cookie'], 'sid=app');
      expect(response.headers.value('content-encoding'), isNull);
      expect(response.headers.value('etag'), isNull);
      expect(
        await utf8.decoder.bind(response).join(),
        '<script src="/port-forward/12/app.js"></script>',
      );
    },
  );

  test(
    'keeps redirects and multiple application cookies inside this rule',
    () async {
      final request = await client.getUrl(url('/port-forward/12/redirect'));
      request.followRedirects = false;
      final response = await request.close();
      expect(
        response.headers.value('location'),
        '/port-forward/12/login?next=1',
      );
      await response.drain<void>();
      final cookies = await (await client.getUrl(
        url('/port-forward/12/cookies'),
      )).close();
      final values = cookies.headers['set-cookie']!;
      expect(values, hasLength(2));
      expect(values[0], contains('hdpf_12_sid=one'));
      expect(values[0], contains('Path=/port-forward/12/'));
      expect(values[0], contains('HttpOnly'));
      expect(values[1], contains('Path=/port-forward/12/settings'));
      expect(values[1].toLowerCase(), isNot(contains('domain=')));
      await cookies.drain<void>();
    },
  );

  test('preserves encoded delimiters in an upstream path segment', () async {
    final response = await (await client.getUrl(
      url('/port-forward/12/files/a%2Fb%3Fc%23d'),
    )).close();
    expect(seenPath, 'files/a%2Fb%3Fc%23d');
    await response.drain<void>();
  });

  test(
    'passes POST, binary, SSE and upstream 404 without SPA fallback',
    () async {
      final request = await client.postUrl(url('/port-forward/12/echo'));
      request.write('payload');
      final response = await request.close();
      expect(await utf8.decoder.bind(response).join(), 'payload');
      final binary = await (await client.getUrl(
        url('/port-forward/12/binary'),
      )).close();
      expect(await binary.fold<List<int>>([], (a, b) => a..addAll(b)), [
        0,
        255,
        128,
      ]);
      final stream = await (await client.getUrl(
        url('/port-forward/12/stream'),
      )).close();
      expect(await utf8.decoder.bind(stream).join(), 'data: hello\n\n');
      final missing = await (await client.getUrl(
        url('/port-forward/12/missing'),
      )).close();
      expect(missing.statusCode, 404);
      expect(await utf8.decoder.bind(missing).join(), 'upstream missing');
    },
  );

  test(
    'preserves query when adding trailing slash and rejects stopped rules',
    () async {
      final request = await client.getUrl(url('/port-forward/12?next=1'));
      request.followRedirects = false;
      final response = await request.close();
      expect(response.headers.value('location'), '/port-forward/12/?next=1');
      await response.drain<void>();
      service.running = false;
      final stopped = await (await client.getUrl(
        url('/port-forward/12/'),
      )).close();
      expect(stopped.statusCode, 404);
      await stopped.drain<void>();
    },
  );

  test('bridges WebSocket and only forwards this application cookie', () async {
    final channel = await WebSocket.connect(
      url('/port-forward/12/ws?token=1').replace(scheme: 'ws').toString(),
      headers: {
        'cookie': 'hostdeck_session=secret; hdpf_12_sid=app; hdpf_13_sid=other',
      },
    ).timeout(const Duration(seconds: 5));
    channel.add('ping');
    expect(await channel.first.timeout(const Duration(seconds: 5)), 'ping');
    expect(seenPath, 'ws?token=1');
    expect(seenHeaders['cookie'], 'sid=app');
    await channel.close();
  });

  test(
    'requires HostDeck authentication and rejects foreign websocket origins',
    () async {
      final authenticated = PortForwardHttpProxy(
        service: service,
        accessService: AccessAuthService(password: 'secret'),
      );
      try {
        final response = await authenticated.handle(
          Request('GET', url('/port-forward/12/')),
        );
        expect(response.statusCode, 401);
      } finally {
        await authenticated.dispose();
      }
      final response = await proxy.handle(
        Request(
          'GET',
          url('/port-forward/12/ws'),
          headers: {
            'upgrade': 'websocket',
            'origin': 'https://foreign.example',
            'host': '127.0.0.1:${server.port}',
          },
        ),
      );
      expect(response.statusCode, 403);
    },
  );
}

class _Resolver extends PortForwardService {
  final int port;
  bool running = true;
  _Resolver(this.port) : super(SshService());

  @override
  HttpProxyUpstream? resolveHttp(String id) =>
      running && id == '12' ? HttpProxyUpstream('127.0.0.1', port) : null;
}
