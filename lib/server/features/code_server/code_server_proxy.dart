import 'package:logging/logging.dart';
import 'package:shelf/shelf.dart';

import 'package:host_deck/server/core/http/access_log.dart';
import 'package:host_deck/server/core/http/path_http_proxy.dart';
import 'package:host_deck/server/features/code_server/code_server_models.dart';
import 'package:host_deck/server/features/code_server/ide_port_proxy_rewriter.dart';

/// Keeps the IDE workspace untouched and adapts only its port previews.
class CodeServerProxy extends PathHttpProxy {
  final Logger _log;

  CodeServerProxy({
    required CodeServerUpstreamResolver resolver,
    required super.accessService,
    Logger? log,
  }) : _log = log ?? Logger('CodeServerProxy'),
       super(
         resolve: (id) async {
           final upstream = await resolver.resolve(id);
           return upstream == null
               ? null
               : HttpProxyUpstream(upstream.host, upstream.port);
         },
         routePrefix: 'ide',
         validId: (id) => RegExp(r'^[a-f0-9]{8,}$').hasMatch(id),
         rewriterForPath: IdePortProxyRewriter.fromPath,
         log: log ?? Logger('CodeServerProxy'),
       );

  static bool handlesRequest(Request request) =>
      request.url.pathSegments.firstOrNull == 'ide';

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
