import 'package:flutter_test/flutter_test.dart';
import 'package:host_deck/server/features/code_server/ide_port_proxy_rewriter.dart';

void main() {
  const prefix = '/ide/abc12345/proxy/5173';
  final rewriter = IdePortProxyRewriter.fromPath('$prefix/')!;

  test('only adapts valid port-forward paths', () {
    expect(IdePortProxyRewriter.fromPath('/ide/abc12345/'), isNull);
    expect(IdePortProxyRewriter.fromPath('/ide/abc12345/proxy/65536/'), isNull);
  });

  test('rewrites module and CSS assets while preserving other URLs', () {
    final source = '''import x from "/src/app.ts";
import("/node_modules/pkg.js");
const cdn = "//cdn.example/a.js";
const relative = "./local.js";
const existing = "$prefix/src/app.ts";''';
    final result = rewriter.rewrite(
      source,
      'application/javascript',
      '/proxy/5173/app.js',
    );
    expect(result, contains('from "$prefix/src/app.ts"'));
    expect(result, contains('import("$prefix/node_modules/pkg.js")'));
    expect(result, contains('"//cdn.example/a.js"'));
    expect(result, contains('"./local.js"'));
    expect(result, isNot(contains('$prefix$prefix')));
    expect(
      rewriter.rewrite('a{background:url(/images/bg.png)}', 'text/css', ''),
      'a{background:url($prefix/images/bg.png)}',
    );
  });

  test('keeps JavaScript separators and HMR identities unchanged', () {
    const source =
        'const separator = "/"; const route = {path: "/settings"}; createHotContext("/src/app.ts"); '
        'import.meta.hot.accept(["/src/a.ts", "/src/b.ts"], cb);';
    expect(rewriter.rewrite(source, 'text/javascript', '/app.js'), source);
    final base = rewriter.rewrite(
      'const base = "/" || "/";',
      'text/javascript',
      '/@vite/client',
    );
    expect(base, 'const base = "$prefix/";');
  });

  test('Vite HMR uses public origin and forwarded websocket path', () {
    final result = rewriter.rewrite(
      'const socketHost = makeSocketHost();',
      'text/javascript',
      '/proxy/5173/@vite/client',
    );
    expect(
      result,
      'const socketHost = new URL(import.meta.url).host + "$prefix/";',
    );
  });
}
