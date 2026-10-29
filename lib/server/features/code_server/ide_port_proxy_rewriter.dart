import 'dart:convert';

/// Response adaptation is restricted to code-server's forwarded application URLs.
class IdePortProxyRewriter {
  final String prefix;

  IdePortProxyRewriter._(this.prefix);

  static IdePortProxyRewriter? fromPath(String path) {
    final match = RegExp(
      r'^/ide/([a-f0-9]{8,})/proxy/([0-9]+)(?:/|$)',
    ).firstMatch(path);
    if (match == null) return null;
    final port = int.tryParse(match[2]!);
    if (port == null || port < 1 || port > 65535) return null;
    final sessionId = match[1]!;
    return IdePortProxyRewriter._('/ide/$sessionId/proxy/$port');
  }

  String rewriteUrl(String value) {
    if (!value.startsWith('/') ||
        value.startsWith('//') ||
        value == prefix ||
        value.startsWith('$prefix/')) {
      return value;
    }
    return '$prefix$value';
  }

  bool rewritesContentType(String contentType) {
    final type = contentType.split(';').first.trim().toLowerCase();
    return const {
      'text/html',
      'text/css',
      'text/javascript',
      'application/javascript',
      'application/x-javascript',
    }.contains(type);
  }

  String rewrite(String source, String contentType, String path) {
    // Keep protocol-relative and already-prefixed URLs intact. Root-relative
    // literals include HTML attributes, ESM imports, assets and Vite's base.
    var result = source.replaceAllMapped(
      RegExp(r'''(["'])(/[^\s"'<>\x60\\]*)\1'''),
      (match) {
        final value = match[2]!;
        // A lone slash in JavaScript is commonly a separator, not a URL.
        final isScript = contentType.contains('javascript');
        if (isScript && value == '/') return match[0]!;
        // HMR identities must match the unmodified paths sent by Vite.
        final before = source.substring(0, match.start);
        if (isScript &&
            RegExp(
              r'(?:createHotContext|\.accept)\(\s*(?:\[[^\]]*)?$',
            ).hasMatch(before)) {
          return match[0]!;
        }
        if (isScript) {
          // Route definitions and arbitrary strings are not resource URLs.
          final urlContext = RegExp(
            r'(?:\bfrom|\bimport|\bimport\s*\(|\bfetch\s*\(|\bnew\s+URL\s*\(|\b(?:src|href|url)\s*[:=])\s*$',
          ).hasMatch(before);
          final assetPath = RegExp(
            r'\.[a-zA-Z0-9]{1,8}(?:[?#].*)?$',
          ).hasMatch(value);
          if (!urlContext && !assetPath) return match[0]!;
        }
        final quote = match[1]!;
        return '$quote${rewriteUrl(value)}$quote';
      },
    );
    if (contentType.toLowerCase().contains('text/css')) {
      result = result.replaceAllMapped(
        RegExp(r'url\(\s*(/[^\s)]+)\s*\)'),
        (match) => 'url(${rewriteUrl(match[1]!)})',
      );
    }
    // Vite constructs its HMR URL using template literals. Use the browser's
    // public origin and forwarded path even when hmr.port is configured.
    if (path.split('?').first.endsWith('/@vite/client')) {
      final socketBase = jsonEncode('$prefix/');
      result = result.replaceAllMapped(
        RegExp(r'const (base(?:\$[0-9]+)?) = [^;]+;'),
        (match) => 'const ${match[1]} = $socketBase;',
      );
      result = result.replaceAll(
        RegExp(r'const socketHost = [^;]+;'),
        'const socketHost = new URL(import.meta.url).host + $socketBase;',
      );
    }
    return result;
  }
}
