import 'dart:async';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:shelf/shelf.dart';

import 'package:host_deck/server/features/access/access_auth_service.dart';
import 'package:host_deck/server/features/code_server/code_server_models.dart';

/// 把 `/ide/<sessionId>/...` 反向代理到 code-server。
///
/// 关键点：
/// - 必须剥离 `/ide/<sessionId>` 前缀（code-server 的 Express 路由挂在根）。
/// - 上游 404 原样返回，不能交给 SPA fallback。
/// - WS 用 `request.hijack` 拿原始 socket，重放握手头到上游。
/// - 不把 HostDeck 的 Cookie/Authorization 透给上游。
class CodeServerProxy {
  final CodeServerUpstreamResolver _resolver;
  final AccessAuthService _accessService;
  final Logger _log;
  final HttpClient _client;

  CodeServerProxy({
    required CodeServerUpstreamResolver resolver,
    required AccessAuthService accessService,
    Logger? log,
  }) : _resolver = resolver,
       _accessService = accessService,
       _log = log ?? Logger('CodeServerProxy'),
       _client = HttpClient()
         ..autoUncompress = false
         ..connectionTimeout = const Duration(seconds: 10);

  Future<Response> handle(Request request) async {
    final principal = _accessService.authenticate(request);
    if (_accessService.enabled && principal == null) {
      return Response(
        401,
        body: 'Authentication required',
        headers: {'content-type': 'text/plain; charset=utf-8'},
      );
    }

    final segments = request.url.pathSegments;
    if (segments.length < 2 || segments[0] != 'ide') {
      return Response.notFound('Not found');
    }
    final sessionId = segments[1];
    if (!_isSessionId(sessionId)) {
      return Response.notFound('Not found');
    }

    final isUpgrade = request.headers['upgrade']?.toLowerCase() == 'websocket';
    if (isUpgrade && !_hasSameOrigin(request)) {
      return Response(403, body: 'Invalid request origin');
    }

    final upstream = await _resolver.resolve(sessionId);
    if (upstream == null) {
      return Response.notFound('IDE session not found');
    }

    // `/ide/<id>` 没有尾斜杠时，相对资源路径会解析到错误位置。
    if (segments.length == 2 && !request.url.path.endsWith('/')) {
      final location = '${request.requestedUri.path}/';
      return Response.movedPermanently(location);
    }

    final upstreamPath = _mapPath(segments);
    if (upstreamPath == null) {
      return Response(400, body: 'Invalid IDE path');
    }
    final upstreamQuery = request.url.hasQuery ? request.url.query : null;

    if (isUpgrade) {
      _proxyWebSocket(request, upstream, upstreamPath, upstreamQuery);
      throw StateError('unreachable');
    }

    return _proxyHttp(request, upstream, upstreamPath, upstreamQuery);
  }

  Future<Response> _proxyHttp(
    Request request,
    CodeServerUpstream upstream,
    String path,
    String? query,
  ) async {
    final uri = Uri(
      scheme: 'http',
      host: upstream.host,
      port: upstream.port,
      path: path,
      query: query,
    );

    HttpClientRequest? upstreamRequest;
    try {
      upstreamRequest = await _client
          .openUrl(request.method, uri)
          .timeout(const Duration(seconds: 15));
      upstreamRequest.followRedirects = false;
      request.headers.forEach((name, value) {
        if (_skipRequestHeader(name)) return;
        upstreamRequest!.headers.set(name, value);
      });
      upstreamRequest.headers.set('accept-encoding', 'gzip');
      if (request.method != 'GET' && request.method != 'HEAD') {
        await upstreamRequest.addStream(request.read());
      }
      final response = await upstreamRequest.close().timeout(
        const Duration(minutes: 5),
      );

      final headers = <String, String>{};
      response.headers.forEach((name, values) {
        if (_skipResponseHeader(name)) return;
        headers[name] = values.join(',');
      });

      return Response(
        response.statusCode,
        body: response,
        headers: headers,
        context: const {'shelf.io.buffer_output': false},
      );
    } on TimeoutException {
      upstreamRequest?.abort();
      return Response(504, body: 'IDE upstream timeout');
    } on SocketException catch (error) {
      _log.warning('IDE upstream connection failed: $error');
      return Response(502, body: 'IDE upstream unavailable');
    }
  }

  void _proxyWebSocket(
    Request request,
    CodeServerUpstream upstream,
    String path,
    String? query,
  ) {
    final key = request.headers['sec-websocket-key'];
    final version = request.headers['sec-websocket-version'] ?? '13';
    final protocol = request.headers['sec-websocket-protocol'];

    request.hijack((channel) {
      unawaited(() async {
        Socket? socket;
        try {
          socket = await Socket.connect(
            upstream.host,
            upstream.port,
            timeout: const Duration(seconds: 10),
          );
          final buffer = StringBuffer()
            ..write('GET $path')
            ..write(query == null || query.isEmpty ? '' : '?$query')
            ..write(' HTTP/1.1\r\n')
            ..write('Host: ${upstream.host}:${upstream.port}\r\n')
            ..write('Origin: http://${upstream.host}:${upstream.port}\r\n')
            ..write('Upgrade: websocket\r\n')
            ..write('Connection: Upgrade\r\n')
            ..write('Sec-WebSocket-Key: $key\r\n')
            ..write('Sec-WebSocket-Version: $version\r\n');
          if (protocol != null && protocol.isNotEmpty) {
            buffer.write('Sec-WebSocket-Protocol: $protocol\r\n');
          }
          buffer.write('\r\n');
          socket.add(buffer.toString().codeUnits);
          await socket.flush();

          final done = Completer<void>();
          socket.listen(
            channel.sink.add,
            onError: (Object _) {
              if (!done.isCompleted) done.complete();
            },
            onDone: () {
              try {
                channel.sink.close();
              } catch (_) {}
              if (!done.isCompleted) done.complete();
            },
            cancelOnError: false,
          );
          channel.stream.listen(
            socket.add,
            onError: (Object _) {
              socket?.destroy();
              if (!done.isCompleted) done.complete();
            },
            onDone: () {
              socket?.destroy();
              if (!done.isCompleted) done.complete();
            },
            cancelOnError: true,
          );
          await done.future;
        } catch (error, stackTrace) {
          _log.fine('IDE WebSocket proxy closed: $error', error, stackTrace);
        } finally {
          socket?.destroy();
          try {
            await channel.sink.close();
          } catch (_) {
            // 对端已关闭时忽略。
          }
        }
      }());
    });
  }

  static String? _mapPath(List<String> segments) {
    // segments: ide / <sessionId> / ...rest
    final rest = segments.sublist(2);
    if (rest.isEmpty) return '/';
    if (rest.any((segment) => segment == '..' || segment == '.')) {
      return null;
    }
    return '/${rest.join('/')}';
  }

  static bool _isSessionId(String value) =>
      value.length >= 8 && RegExp(r'^[a-f0-9]+$').hasMatch(value);

  bool _hasSameOrigin(Request request) {
    final origin = request.headers['origin'];
    final host = request.headers['host'];
    // 非浏览器客户端可能不带 Origin；浏览器一定带，安全检查仍生效。
    if (origin == null) return true;
    if (host == null) return false;
    final uri = Uri.tryParse(origin);
    if (uri == null) return false;
    return uri.authority.toLowerCase() == host.toLowerCase();
  }

  static bool _skipRequestHeader(String name) {
    const skip = {
      'host',
      'connection',
      'keep-alive',
      'transfer-encoding',
      'upgrade',
      'accept-encoding',
      'cookie',
      'authorization',
      'content-length',
      'proxy-connection',
    };
    return skip.contains(name.toLowerCase());
  }

  static bool _skipResponseHeader(String name) {
    const skip = {
      'connection',
      'keep-alive',
      'transfer-encoding',
      'content-length',
      'proxy-connection',
    };
    return skip.contains(name.toLowerCase());
  }

  Future<void> dispose() async {
    _client.close(force: true);
  }
}
