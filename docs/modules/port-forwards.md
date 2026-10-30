# 端口转发

## 模式与入口

- TCP：绑定 HostDeck 后端所在机器的 `bindHost:localPort`，每条连接经 SSH 转发到 `remoteHost:remotePort`。
- HTTP：浏览器通过 `/port-forward/<ruleId>/` 访问，复用 HostDeck 主服务端口。后端只创建 `127.0.0.1:0` 内部桥接监听，远端仍经 SSH 访问，不要求额外开放防火墙端口。

前端入口为 `host-deck-ui/src/views/PortForward/index.vue`。Docker 容器的“端口操作”弹窗支持为已发布的 TCP 端口快速创建 HTTP 转发；目标取 Docker 窗口的 SSH 连接和宿主机发布地址、端口。通配绑定地址转换为回环地址，显式绑定地址保持原值。未发布端口和 UDP 端口不提供 HTTP 快捷创建。

## API 与存储

管理接口沿用 `/api/port-forwards` 的增删改查及 `/<id>/start`、`/<id>/stop`。

创建和更新新增 `protocol: "tcp" | "http"`，省略时默认 `tcp`。HTTP 不需要 `bindHost`、`localPort`，存储的 `localPort` 为 0；启动后的内部随机端口不会写入规则。响应中的 HTTP 规则增加 `accessPath: "/port-forward/<ruleId>/"`，TCP 为 null。前端按当前浏览器 origin 生成完整 URL，适配 HTTPS 入口和 Vite 同源开发代理。

数据库 v22 给已有规则增加默认值为 `tcp` 的 `protocol` 字段。进程启动时仍重置规则运行标记，保存的规则不会自动连接 SSH。Docker 快捷创建复用同一活动 SSH 连接上目标完全相同的运行中 HTTP 规则，并合并并发点击。

## 代理与生命周期

`core/http/path_http_proxy.dart` 和 `proxy_content_rewriter.dart` 提供公共代理能力，远程 IDE 与 HTTP 转发共用。代理中间件在 SPA fallback 之前截获请求，上游 404 原样返回。支持 HTTP 请求体、WebSocket、SSE、二进制响应和 gzip 文本适配；HTML/CSS/JavaScript 根路径资源、根路径重定向及 Vite HMR 使用公开转发前缀。

HTTP 转发复用 HostDeck 认证。不会向应用发送 HostDeck 的 Authorization 或会话 Cookie。应用 Set-Cookie 按规则增加名称前缀、改写 Path、移除 Domain；返回上游时恢复原 Cookie 名称，仅转发当前规则的 Cookie。多个 Set-Cookie 保持独立。此方案适用于常规服务端会话；直接按原名读取 `document.cookie` 的前端代码可能需要应用侧适配。

运行中的 HTTP 规则持有 SSH 租约，代理访问会 touch 连接。停止、删除、更新规则和 SSH 断开时关闭内部监听与已建立的 socket/channel，迟到的 SSH 通道也会关闭。停止后的代理地址返回 404。设置中的后端端口列表会标明 HTTP 内部隧道及其公开路径。

## 兼容范围

目标上游为 HTTP，浏览器侧可通过 HostDeck 的 HTTPS 入口访问。路径适配范围与 IDE 端口预览一致：动态构造的根路径、写死的绝对域名、自定义 WebSocket URL、Service Worker 和依赖站点根目录的前端路由，可能需要配置应用自己的 base/public path。转发应用与 HostDeck 同源，适合运行可信应用。

## 验证

- `fvm flutter test test/port_forward_http_proxy_test.dart test/port_forward_service_test.dart test/port_forward_repository_test.dart test/code_server_proxy_test.dart test/ide_port_proxy_rewriter_test.dart`
- `pnpm --dir host-deck-ui exec vitest run src/views/Docker/hooks/__tests__/dockerPortForward.spec.ts src/views/Docker/hooks/__tests__/useDockerView.spec.ts`
- `fvm flutter analyze`
- `pnpm --dir host-deck-ui exec vue-tsc -p tsconfig.app.json --noEmit`
- `pnpm --dir host-deck-ui build`
