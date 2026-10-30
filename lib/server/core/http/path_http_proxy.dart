import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:shelf/shelf.dart';

import 'package:host_deck/server/features/access/access_auth_service.dart';
import 'package:host_deck/server/core/http/proxy_content_rewriter.dart';

class HttpProxyUpstream {
  final String host;
  final int port;

  const HttpProxyUpstream(this.host, this.port);
}

/// HTTP and raw WebSocket forwarding beneath a two-segment public prefix.
class PathHttpProxy {
  final Future<HttpProxyUpstream?> Function(String id) _resolve;
  final AccessAuthService _accessService;
  final String routePrefix;
  final bool Function(String id) validId;
  final ProxyContentRewriter? Function(String path) rewriterForPath;
  final bool applicationCookies;
  final Logger _log;
  final HttpClient _client;

  PathHttpProxy({
    required Future<HttpProxyUpstream?> Function(String id) resolve,
    required AccessAuthService accessService,
    required this.routePrefix,
    required this.validId,
    required this.rewriterForPath,
    this.applicationCookies = false,
    Logger? log,
  }) : _resolve = resolve,
       _accessService = accessService,
       _log = log ?? Logger('PathHttpProxy'),
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
    if (segments.length < 2 || segments[0] != routePrefix) {
      return Response.notFound('Not found');
    }
    final sessionId = segments[1];
    if (!validId(sessionId)) {
      return Response.notFound('Not found');
    }

    final isUpgrade = request.headers['upgrade']?.toLowerCase() == 'websocket';
    if (isUpgrade && !_hasSameOrigin(request)) {
      return Response(403, body: 'Invalid request origin');
    }

    final upstream = await _resolve(sessionId);
    if (upstream == null) {
      return Response.notFound('Forward not found or stopped');
    }

    // A trailing slash keeps relative application resources under this prefix.
    if (segments.length == 2 && !request.url.path.endsWith('/')) {
      final location =
          '${request.requestedUri.path}/'
          '${request.url.hasQuery ? '?${request.url.query}' : ''}';
      return Response.movedPermanently(location);
    }

    final upstreamPath = _mapPath(segments);
    if (upstreamPath == null) {
      return Response(400, body: 'Invalid proxy path');
    }
    final upstreamQuery = request.url.hasQuery ? request.url.query : null;

    if (isUpgrade) {
      _proxyWebSocket(
        request,
        upstream,
        upstreamPath,
        upstreamQuery,
        sessionId,
      );
      throw StateError('unreachable');
    }

    return _proxyHttp(request, upstream, upstreamPath, upstreamQuery);
  }

  Future<Response> _proxyHttp(
    Request request,
    HttpProxyUpstream upstream,
    String path,
    String? query,
  ) async {
    final uri = Uri(
      scheme: 'http',
      host: upstream.host,
      port: upstream.port,
      pathSegments: ['', ...request.url.pathSegments.sublist(2)],
      query: query,
    );

    HttpClientRequest? upstreamRequest;
    try {
      upstreamRequest = await _client
          .openUrl(request.method, uri)
          .timeout(const Duration(seconds: 15));
      upstreamRequest.followRedirects = false;
      final portProxy = rewriterForPath(request.requestedUri.path);
      request.headers.forEach((name, value) {
        if (_skipRequestHeader(name)) return;
        if (portProxy != null &&
            const {
              'if-none-match',
              'if-modified-since',
              'range',
              'if-range',
            }.contains(name.toLowerCase())) {
          return;
        }
        upstreamRequest!.headers.set(name, value);
      });
      if (applicationCookies) {
        final cookie = _upstreamCookie(request);
        if (cookie.isNotEmpty) upstreamRequest.headers.set('cookie', cookie);
      }
      upstreamRequest.headers.set(
        'accept-encoding',
        portProxy == null ? 'gzip' : 'identity',
      );
      if (request.method != 'GET' && request.method != 'HEAD') {
        await upstreamRequest.addStream(request.read());
      }
      final response = await upstreamRequest.close().timeout(
        const Duration(minutes: 5),
      );

      final headers = <String, Object>{};
      response.headers.forEach((name, values) {
        if (_skipResponseHeader(name)) return;
        if (name == 'set-cookie' && applicationCookies) {
          headers[name] = values
              .map((value) => _rewriteCookie(value, request))
              .whereType<String>()
              .toList();
        } else {
          headers[name] = values;
        }
      });

      String? header(String name) =>
          (headers[name] as List<String>?)?.join(',');
      final location = header('location');
      if (portProxy != null && location != null) {
        headers['location'] = portProxy.rewriteUrl(location);
      }
      Object body = response;
      final contentType = header('content-type') ?? '';
      if (portProxy != null &&
          request.method != 'HEAD' &&
          response.statusCode != 304 &&
          portProxy.rewritesContentType(contentType)) {
        Stream<List<int>> bytes = response;
        if (header('content-encoding') == 'gzip') {
          bytes = response.transform(gzip.decoder);
        } else if (headers.containsKey('content-encoding') &&
            header('content-encoding') != 'identity') {
          return Response(
            response.statusCode,
            body: response,
            headers: headers,
          );
        }
        final source = await utf8.decoder.bind(bytes).join();
        body = portProxy.rewrite(source, contentType, path);
        headers.remove('content-encoding');
        headers.remove('etag');
        headers.remove('content-md5');
        headers['cache-control'] = 'no-store';
      }

      return Response(
        response.statusCode,
        body: body,
        headers: headers,
        context: const {'shelf.io.buffer_output': false},
      );
    } on TimeoutException {
      upstreamRequest?.abort();
      return Response(504, body: 'Proxy upstream timeout');
    } on SocketException catch (error) {
      _log.warning('Proxy upstream connection failed: $error');
      return Response(502, body: 'Proxy upstream unavailable');
    } on HttpException catch (error) {
      upstreamRequest?.abort();
      _log.warning('Proxy upstream HTTP error: $error');
      return Response(502, body: 'Proxy upstream unavailable');
    }
  }

  void _proxyWebSocket(
    Request request,
    HttpProxyUpstream upstream,
    String path,
    String? query,
    String sessionId,
  ) {
    final key = request.headers['sec-websocket-key'];
    final version = request.headers['sec-websocket-version'] ?? '13';
    final protocol = request.headers['sec-websocket-protocol'];

    request.hijack((channel) {
      unawaited(() async {
        final startedAt = DateTime.now();
        Socket? socket;
        var browserToUpstreamBytes = 0;
        var upstreamToBrowserBytes = 0;
        var firstClose = 'none';
        Object? lastError;
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
          if (applicationCookies) {
            final cookie = _upstreamCookie(request);
            if (cookie.isNotEmpty) buffer.write('Cookie: $cookie\r\n');
          }
          buffer.write('\r\n');
          socket.add(buffer.toString().codeUnits);
          await socket.flush();
          _log.fine(
            'Proxy WebSocket opened route=$routePrefix id=$sessionId path=$path',
          );

          final done = Completer<void>();
          final upstreamSocket = socket;
          // 对端先断开时 flush 失败会以异步错误出现在 done 上，必须吞掉，
          // 否则会变成进程级的 "Asynchronous error: Broken pipe"。
          unawaited(
            upstreamSocket.done.then<void>(
              (_) {},
              onError: (Object error) {
                lastError ??= error;
                if (!done.isCompleted) done.complete();
              },
            ),
          );
          socket.listen(
            (data) {
              browserToUpstreamBytes += data.length;
              try {
                channel.sink.add(data);
              } catch (error) {
                lastError ??= error;
                if (!done.isCompleted) done.complete();
              }
            },
            onError: (Object error) {
              lastError = error;
              if (!done.isCompleted) done.complete();
            },
            onDone: () {
              if (firstClose == 'none') firstClose = 'upstream';
              try {
                channel.sink.close();
              } catch (_) {}
              if (!done.isCompleted) done.complete();
            },
            cancelOnError: false,
          );
          channel.stream.listen(
            (data) {
              upstreamToBrowserBytes += data.length;
              try {
                upstreamSocket.add(data);
              } catch (error) {
                lastError ??= error;
                if (!done.isCompleted) done.complete();
              }
            },
            onError: (Object error) {
              lastError = error;
              socket?.destroy();
              if (!done.isCompleted) done.complete();
            },
            onDone: () {
              if (firstClose == 'none') firstClose = 'browser';
              socket?.destroy();
              if (!done.isCompleted) done.complete();
            },
            cancelOnError: true,
          );
          await done.future;
        } catch (error, stackTrace) {
          lastError = error;
          _log.warning(
            'Proxy WebSocket error route=$routePrefix id=$sessionId path=$path: $error',
            error,
            stackTrace,
          );
        } finally {
          socket?.destroy();
          try {
            await channel.sink.close();
          } catch (_) {
            // 对端已关闭时忽略。
          }
          final durationMs = DateTime.now()
              .difference(startedAt)
              .inMilliseconds;
          _log.info(
            'Proxy WebSocket closed route=$routePrefix id=$sessionId path=$path '
            'firstClose=$firstClose durationMs=$durationMs '
            'browserToUpstreamBytes=$browserToUpstreamBytes '
            'upstreamToBrowserBytes=$upstreamToBrowserBytes '
            'error=$lastError',
          );
        }
      }());
    });
  }

  static String? _mapPath(List<String> segments) {
    // Preserve encoded slashes and delimiters inside individual path segments.
    final rest = segments.sublist(2);
    if (rest.isEmpty) return '/';
    if (rest.any((segment) => segment == '..' || segment == '.')) {
      return null;
    }
    return Uri(pathSegments: ['', ...rest]).path;
  }

  String _cookiePrefix(Request request) =>
      'hdpf_${request.url.pathSegments[1]}_';

  String _upstreamCookie(Request request) {
    final prefix = _cookiePrefix(request);
    return (request.headers['cookie'] ?? '')
        .split(';')
        .map((part) => part.trim())
        .where((part) => part.startsWith(prefix) && part.contains('='))
        .map((part) => part.substring(prefix.length))
        .where((part) => !part.startsWith('${AccessAuthService.cookieName}='))
        .join('; ');
  }

  String? _rewriteCookie(String value, Request request) {
    try {
      final cookie = Cookie.fromSetCookieValue(value);
      if (cookie.name == AccessAuthService.cookieName) return null;
      final prefix = '/$routePrefix/${request.url.pathSegments[1]}';
      final rewritten =
          Cookie('${_cookiePrefix(request)}${cookie.name}', cookie.value)
            ..path =
                '$prefix${cookie.path?.startsWith('/') == true ? cookie.path : '/'}'
            ..httpOnly = cookie.httpOnly
            ..secure = cookie.secure
            ..sameSite = cookie.sameSite
            ..expires = cookie.expires
            ..maxAge = cookie.maxAge;
      return rewritten.toString();
    } on FormatException {
      return null;
    }
  }

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
