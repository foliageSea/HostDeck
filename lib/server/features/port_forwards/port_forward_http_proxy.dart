import 'package:logging/logging.dart';
import 'package:shelf/shelf.dart';
import 'package:host_deck/server/core/http/access_log.dart';
import 'package:host_deck/server/core/http/path_http_proxy.dart';
import 'package:host_deck/server/core/http/proxy_content_rewriter.dart';
import 'package:host_deck/server/features/port_forwards/port_forward_service.dart';

class PortForwardHttpProxy extends PathHttpProxy {
  static final _log = Logger('PortForwardHttpProxy');

  PortForwardHttpProxy({
    required PortForwardService service,
    required super.accessService,
  }) : super(
         resolve: (id) async => service.resolveHttp(id),
         routePrefix: 'port-forward',
         validId: (id) => RegExp(r'^[1-9][0-9]*$').hasMatch(id),
         rewriterForPath: (path) => ProxyContentRewriter(
           '/port-forward/${Uri.parse(path).pathSegments[1]}',
         ),
         applicationCookies: true,
         log: _log,
       );

  static bool handlesRequest(Request request) =>
      request.url.pathSegments.firstOrNull == 'port-forward';

  @override
  Future<Response> handle(Request request) async {
    final stopwatch = Stopwatch()..start();
    try {
      final response = await super.handle(request);
      stopwatch.stop();
      _log.fine(
        formatAccessLog(request, response.statusCode, stopwatch.elapsed),
      );
      return response;
    } on HijackException {
      rethrow;
    } catch (error, stackTrace) {
      stopwatch.stop();
      _log.severe(
        formatAccessLog(request, 500, stopwatch.elapsed),
        error,
        stackTrace,
      );
      rethrow;
    }
  }
}

Middleware portForwardProxyMiddleware(PortForwardHttpProxy proxy) =>
    (innerHandler) =>
        (request) => PortForwardHttpProxy.handlesRequest(request)
        ? proxy.handle(request)
        : innerHandler(request);
