import 'package:host_deck/server/core/http/path_http_proxy.dart';
import 'package:host_deck/server/features/code_server/code_server_models.dart';
import 'package:host_deck/server/features/code_server/ide_port_proxy_rewriter.dart';

/// Keeps the IDE workspace untouched and adapts only its port previews.
class CodeServerProxy extends PathHttpProxy {
  CodeServerProxy({
    required CodeServerUpstreamResolver resolver,
    required super.accessService,
    super.log,
  }) : super(
         resolve: (id) async {
           final upstream = await resolver.resolve(id);
           return upstream == null
               ? null
               : HttpProxyUpstream(upstream.host, upstream.port);
         },
         routePrefix: 'ide',
         validId: (id) => RegExp(r'^[a-f0-9]{8,}$').hasMatch(id),
         rewriterForPath: IdePortProxyRewriter.fromPath,
       );
}
