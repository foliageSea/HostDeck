import 'package:shelf/shelf.dart';

import 'package:host_deck/server/features/code_server/code_server_proxy.dart';

/// 只接管 `/ide/...`，其余请求原样交给后续 handler。
///
/// 必须挂在 Pipeline 层：放在 Cascade 尾部时，上游 404 会被 SPA fallback
/// 当成前端路由吞掉。
Middleware codeServerProxyMiddleware(CodeServerProxy proxy) {
  return (innerHandler) {
    return (request) {
      if (!CodeServerProxy.handlesRequest(request)) {
        return innerHandler(request);
      }
      return proxy.handle(request);
    };
  };
}
