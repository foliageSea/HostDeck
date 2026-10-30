import 'package:shelf/shelf.dart';
import 'package:host_deck/server/core/http/path_http_proxy.dart';
import 'package:host_deck/server/core/http/proxy_content_rewriter.dart';
import 'package:host_deck/server/features/port_forwards/port_forward_service.dart';

class PortForwardHttpProxy extends PathHttpProxy {
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
       );
}

Middleware portForwardProxyMiddleware(PortForwardHttpProxy proxy) =>
    (innerHandler) =>
        (request) => request.url.pathSegments.firstOrNull == 'port-forward'
        ? proxy.handle(request)
        : innerHandler(request);
