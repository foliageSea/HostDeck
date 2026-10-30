import 'package:host_deck/server/core/http/proxy_content_rewriter.dart';

/// Only code-server's application preview responses need content adaptation.
class IdePortProxyRewriter extends ProxyContentRewriter {
  IdePortProxyRewriter._(super.prefix);

  static IdePortProxyRewriter? fromPath(String path) {
    final match = RegExp(
      r'^/ide/([a-f0-9]{8,})/proxy/([0-9]+)(?:/|$)',
    ).firstMatch(path);
    if (match == null) return null;
    final port = int.tryParse(match[2]!);
    if (port == null || port < 1 || port > 65535) return null;
    return IdePortProxyRewriter._('/ide/${match[1]}/proxy/$port');
  }
}
