# code-server 后端接入点调研（代理 / 隧道 / 进程管理）

> 任务 task-1｜只读调研 HostDeck Dart 后端（未修改业务代码）
> 证据格式 `文件:行`（仓库相对路径）。【已验证】= 读源码确认；【推测】= 未跑通。
> 本机 web_search / web_fetch 均不可用（401 / 非公网解析），凡涉及 code-server 上游行为一律标【待核实】，交给 distribution.md 补。

## 0. 结论速览

1. HTTP 入口只有一个 shelf `Pipeline → Cascade`（`lib/server/app/server_handlers.dart:144-158`）。新增反向代理不需要改 server_service，只要在这条链上插一层分流；**建议放在 Pipeline 中间件层而不是 cascade 尾部**（理由见 §1.2）。
2. 认证只覆盖 `api/` 前缀（`lib/server/features/access/access_middleware.dart:10-13`）。挂到 `/api/...` 白拿认证+Origin 校验；挂到根路径则完全无鉴权，必须自己调 `AccessAuthService.authenticate`。
3. SSH 隧道能力已够用，且 docker 模块把「本地 TCP 监听 → SSH channel → 后端 HttpClient」完整写过一遍（`docker_socket_tunnel_service.dart:99-127,161-194` + `docker_engine_repository.dart:265-317`），可照抄/抽象成 code-server 上游传输层。
4. 后端**没有长驻子进程托管能力**：只有一次性 `Process.start`（pi bridge、Chrome 启动器），无 PID/日志落盘/重启/健康检查，也无退出清理挂载点。这是「本机自带 code-server」的主要缺口。
5. 反代真正的硬点不是路由，而是：WebSocket upgrade、Host/Origin 重写、code-server 的 base path 限制（【待核实】）、SSH 空闲回收器会掐掉「看起来没人用」的隧道（`lib/server/core/ssh/ssh_service.dart:487-514`）、以及 shelf 只跑 HTTP/1.1。

## 1. 服务组装与可挂载点【已验证】

### 1.1 现状
- 启动：`shelf_io.serve(handler, bindAddress, port)`（`lib/server/app/server_service.dart:99-101`），默认 127.0.0.1:8080（`lib/server/app/server_cli.dart:55,71`）；非 loopback 绑定强制要求凭据（`server_service.dart:68-72`）。
- handler 组装在 `buildServerHandler`（`server_handlers.dart:76-159`），由 `server_service.dart:88-97` 传入 container 的 8 个具名参数（apiRoutes/sshService/staticPath/log/accessService/operationLogService/两个 repository）。**新增代理服务需要在这里加参数**，并同步注册到 container（`lib/server/app/server_container.dart:366-444`）与 `ServerContainer` 字段（:75-100）。
- 层序（`server_handlers.dart:139-158`）：`accessLogMiddleware` → `sshActivityMiddleware` → cascade[ apiHandler(="opLog(access(router))" ) → wallpapers → static → spaFallback ]。
- 静态：`createStaticHandler(staticPath, defaultDocument: 'index.html')`（`server_handlers.dart:86-93`）；SPA fallback 对非 `api/` 路径回 index.html，对 `api/` 只回 404 文本（:95-109）；wallpapers 有独立 immutable 缓存（:111-137，缓存头 :133-134）。
- WebSocket：全部挂在 `/api/ws/*`，用 `shelf_web_socket`:`webSocketHandler`（`lib/server/routes/terminal_routes.dart:6`、`lib/server/routes/system_routes.dart:8-9`；实现 `lib/server/features/terminal/terminal_controller.dart:22-38`，带 20s ping）。
- 路由集中注册（`lib/server/routes/api_routes.dart:81-102`），单文件每模块一个 register 函数，新增路由惯例如 `lib/server/routes/port_forward_routes.dart:9-14`。

### 1.2 三个候选挂载点
| 方案 | 位置 | 收益 | 代价 |
|---|---|---|---|
| A. 路由内挂载 | `ApiRoutes.router` 加 `router.mount('/api/code/...', h)`（`api_routes.dart:82-101`） | 白拿 accessMiddleware（认证+Origin 校验）、Vite 已代理 `/api` 且 `ws:true`（`host-deck-ui/vite.config.ts:169-174`） | URL 前缀是 `/api`，code-server 若发绝对路径资源会 404（base path 问题）；Cookie 与 API 前缀耦合 |
| B. Pipeline 分流（推荐） | `server_handlers.dart:155-158` 加一个 path-prefix 中间件，命中 `code/` 走代理，否则 `return inner(request)` | 不受 cascade 404 语义影响；可独立自鉴权；日志/SSH activity 中间件仍包住 | 需自己鉴权（见 §2） |
| C. cascade.add | `server_handlers.dart:144-145`（wallpaper 之前） | 改动最小 | **危险**：shelf Cascade 默认在 404/405 时继续下一个 handler（`~/.pub-cache/hosted/pub.dev/shelf-1.4.2/lib/src/cascade.dart:70-80,86-92`，默认 `statusCodes = [404, 405]`），上游 404 会被 SPA fallback 吞成 index.html |

### 1.3 WebSocket 代理挂点
- 可直接照 `terminal_controller.dart:22-38` 的形态新增 `GET /api/ws/code-server`（或方案 B 的同样路径），handler 用 `webSocketHandler` 后把浏览器 channel 与上游 channel 双向桥接（现有桥接写法参考 `terminal_controller.dart:147-217`）。
- `webSocketHandler` 内部要求 `request.canHijack`（`~/.pub-cache/hosted/pub.dev/shelf_web_socket-3.0.0/lib/src/web_socket_handler.dart:64-70`），shelf_io 满足；握手校验 Connection/Upgrade/Version=13/Key（同文件 :47-63），可选 `allowedOrigins`（公共 API `lib/shelf_web_socket.dart:42-51`，校验逻辑 :73-78）——不传则不校验 Origin。

## 2. 认证与跨站约束【已验证（源码）/ 未做浏览器实测】

- 中间件只处理 `api/` 前缀，其余直接放行（`access_middleware.dart:10-13`）→ 静态资源、wallpapers、SPA、根路径代理都**不经认证**。
- 公开端点：`api/status`、`api/agent/discovery`、`api/access/state`、`api/access/login`（`access_middleware.dart:15-19`，与 `docs/access-control.md:39` 一致）；未认证返回 401 JSON（:22-32）。
- 额外 Origin 校验：仅当 principal 是 `browserSession` 且路径是 `api/ws/*` 或写方法（POST/PUT/PATCH/DELETE）时，要求 `Origin` 的 authority 等于 `Host`（`access_middleware.dart:34-46,57-63,65-78`）→ 反代若改写了 Host 或用外部域名访问，会让 iframe 内的 WS/写请求 403。
- 凭据：Cookie `hostdeck_session`，`Path=/`、`HttpOnly`、`SameSite=Strict`、`Max-Age` 12h、`Secure` 可选（`lib/server/features/access/access_auth_service.dart:36,58,291-301`）；也接受 `Authorization: Bearer`（:246-271）；会话为进程内内存 Map（:49,315-320，重启即失效）。
- 影响：同源子路径代理（HostDeck 自身 origin 下的 `/code/` 或 `/api/code/`）会带 Cookie，iframe 子资源属同站点请求（SameSite=Strict 只拦跨站点）【规范事实，未实测】；但若把 iframe 直接指向 `127.0.0.1:<port>` 或另一域名，则不带 Cookie、也不进 accessMiddleware，等于裸奔（见 `docs/analysis/code-server/frontend.md` 对应章节）。
- 因此方案 B 的代理层必须自己调用 `AccessAuthService.authenticate(request)`（`access_auth_service.dart:246-271`）并对 `api/ws/` 类升级请求做同源校验，否则等于开了一个无鉴权 IDE 入口；`principalContextKey` 上下文写法见 `access_middleware.dart:48-52`。

## 3. 现有隧道能力评估

### 3.1 PortForwardService：可直接跑 WS，但不是反代
- 绑定本地 `ServerSocket`（`bindHost:localPort`，默认 127.0.0.1，`lib/server/features/port_forwards/port_forward_rule.dart:29-32`；`port_forward_service.dart:73-79`），每个入站 socket 开一条 `client.forwardLocal(remoteHost, remotePort)` 并双向 pipe（`port_forward_service.dart:134-182`，:154-159）→ **纯字节中继，WebSocket 天然透传**（协议无关）。
- 约束：规则需先落库（`port_forward_repository`，`server_container.dart:341-346`）；监听在独立端口（浏览器需能直连该 host:port）；**该端口无任何鉴权**，且 `bindHost` 可配（用户可填 0.0.0.0）→ 直接暴露 code-server 的风险。
- dartssh2 2.22.0 的 `forwardLocal(remoteHost, remotePort, {localHost, localPort})` 只返回 `SSHForwardChannel`，**不是监听器**（`~/.pub-cache/hosted/pub.dev/dartssh2-2.22.0/lib/src/ssh_client.dart:389-403`）→ 想「一次隧道多路复用」必须自己实现监听+每连接建 channel，与 port_forward_service 同构。
- SSH 断开时自动停（`port_forward_service.dart:22,116-125`），容器 dispose 时 stopAll（`server_container.dart:464-470`）。

### 3.2 SecureBrowserTunnelService：SOCKS5，不能给后端反代复用
- `client.forwardDynamic(bindHost: 127.0.0.1, filter: _allowTarget)` 起本地 SOCKS5（`secure_browser_tunnel_service.dart:139-148`），仅拦云元数据地址（:114-130）；用途是给本机 Chrome 加 `--proxy-server=socks5://127.0.0.1:<port>`（`lib/server/features/port_forwards/chrome_launcher.dart:104-112`）。
- 它是「浏览器侧代理」，不是服务端 HTTP 客户端；`dart:io` HttpClient 的 `findProxy` 只支持 HTTP proxy，不支持 SOCKS → 后端反代用不上它（【已验证 API 边界，未实测】）。

### 3.3 Docker 隧道：现成模板（推荐复刻）
- `DockerSocketTunnelService` 起 `127.0.0.1:0` 监听（`lib/server/features/docker/docker_socket_tunnel_service.dart:99-116`），每个连接 `socket ↔ channel` 双向 pipe 并在任一端关闭时整体收尾（:161-194），端点以 `Uri(http, 127.0.0.1:port)` 暴露（:151-155）。
- `DockerEngineRepository` 用 `HttpClient` 打这个 loopback 端点（`lib/server/features/docker/docker_engine_repository.dart:265-317`），并设 `autoUncompress=false`（:67-68）保护 `content-encoding` 透传。
- 缺口：这条路径**不支持 WebSocket**（无 upgrade/hijack），也不做 Host 重写；code-server 需要在此基础上补 WS 分支（`WebSocket.connect` / web_socket_channel 客户端 → `webSocketHandler` 桥接）。

## 4. 进程与远端执行能力

### 4.1 本机子进程【已验证：只有一次性启动】
- `ChromeLauncher`：候选路径探测 `/usr/bin/google-chrome*`、macOS app 路径、Windows 三个位置（`chrome_launcher.dart:154-188`），以 `ProcessStartMode.detached` 启动、**不保留 Process 句柄/退出码**（:141-151）；`--chrome-path` 可覆盖（:52-61）。
- `AiAgentPiBridge`：短命 `Process.start`（`lib/server/features/ai_agent/ai_agent_pi_bridge.dart:54-64`），JSON 走 stdin/stdout，主动 drain stderr 防泄密（:69-70），结束 `process.kill()`（:116-120,123-126）。这就是「一次请求一个进程」的模型，**不支持常驻**。
- 生命周期：`bin/server.dart:53-68` 启动 + `registerServerShutdownHandlers`（`lib/server/app/server_lifecycle.dart:6-36`）；`ServerService.stop` → `container.dispose` 停三个隧道服务（`server_container.dart:464-470`、`server_service.dart:117-129`）。**要杀的 code-server 子进程必须挂进这条链**，现有代码没有该挂载点。
- 双入口：Flutter 调试壳也 `new ServerService()`（`lib/main.dart:51`），子进程能力必须同时覆盖 `bin/server.dart:34-49` 与 `lib/main.dart` 两个入口。
- 能力开关先例：`--enable-secure-browser`/`--chrome-path` 解析（`server_cli.dart:41-44,70-79`）与注入（`bin/server.dart:25-32`）、帮助文案（:102-104）→ code-server 可照抄成 `--enable-code-server`/`--code-server-path`/`--code-server-port`。
- 配置持久化：schema 版本化迁移（`lib/server/core/database/database_service.dart:38-52,604-606`），当前最新 **v21**（:566）→ 新增 code-server 配置表= v22。

### 4.2 远端执行【已验证】
- 只有 `client.run`（`lib/server/core/ssh/ssh_repository.dart:114-127`）与 `client.execute` + 完整封装 `execWithResult`（:134-251：cwd/login shell 探测、stdin、`maxOutputBytes`、取消、默认 **60s 超时** :129-135,229-235）。
- process 模块只有 list/kill，无 start（`lib/server/features/processes/process_service.dart:10,21`；`lib/server/routes/process_routes.dart:6-8`）。
- 结论：远端拉 code-server 必须 `nohup/setsid ... >/log 2>&1 &` 后台化 + 用一次短命令探测端口/健康（60s 超时不能跑前台进程）；没有重启/存活看护。
- 连接回收会在无人「租约」且 120s 无活动时断开（`ssh_service.dart:60-73,487-514`），并在 3 分钟收不到任何字节时判定链路已死（:71,519-538）→ **code-server 隧道必须 `attachLease`**（:409-416），否则浏览器 tab 挂几分钟就会被拆。

## 5. 实现反向代理必须处理的点

1. **WS upgrade**：入站用 `webSocketHandler`（hijack），出站用 `WebSocket.connect`/web_socket_channel；code-server 的 WS 是 binary 帧，桥接时不能按 String 解码（对比 `terminal_controller.dart:192-206` 的文本假定）。
2. **Host 重写**：出站 `HttpClient` 按 URI 自动写 Host；若上游对 Host 敏感需显式 `request.headers.host = ...`；入站 Origin 校验见 §2（`access_middleware.dart:65-78`）。
3. **base path**：已回填（见 §5.3）。code-server 官方 patch 过 base path（`patches/base-path.diff`），代理保留 `/ide/` 前缀即可；但必须 PoC 验证登录跳转、静态资源、Service Worker 与 WS 路径。
4. **流式响应**：响应体用 `Response.ok(stream, headers: ...)`（先例 `lib/server/features/files/file_controller.dart:226-239`；SSE 先例 `lib/server/features/logs/server_log_controller.dart:33-55`），请求体用 `request.read()` 直通，**不要** `readAsString`（会破坏上传/SSE）。
5. **超时**：上游要显式 `connectionTimeout`（先例 `lib/server/features/ai_agent/ai_agent_mcp_service.dart:243`）与响应超时 + `request.abort`（`docker_engine_repository.dart:302-316`），否则卡住的上游会长期占用 handler。
6. **认证注入**：上游确认 `--auth none|password`、`--bind-addr`、`--socket`、`--trusted-origins`、`--idle-timeout-seconds` 均存在（`src/node/cli.ts`）。推荐 `--auth none` + 仅 loopback/SSH 通道 + HostDeck 侧鉴权（`access_auth_service.dart:246-271`）；WS 与 HTTP 必须在同一鉴权面。注意 code-server 的 `ensureOrigin` 会比较 Origin 与 Host（`src/node/http.ts:383-426`），代理需把 Origin/Host 重写为上游地址，或配置 `--trusted-origins`。
7. **压缩/编码**：仓库**没有** gzip/Content-Encoding 中间件（全仓 grep 无），透传时上游客户端需 `autoUncompress=false`（先例 `docker_engine_repository.dart:68`），否则 `content-encoding` 与已解压 body 不匹配。
8. **日志量**：`accessLogMiddleware` 对每请求打 info（`server_handlers.dart:19-52`，WS 走 `HijackException` 直通 :39-41），代理会让日志爆掉，需按前缀静音；`sshActivityMiddleware` 只在 URL 带 `connectionId` 时 touch（:58-68）。
9. **HTTP/1.1 并发**：`shelf_io.serve` 无 HTTP/2（`server_service.dart:100`），浏览器同源 6 连接上限与 IDE 的并行请求可能互堵（【推测】需实测）。
10. **操作日志中间件不误伤**：它按显式 method+path 策略匹配（`lib/server/features/operation_logs/operation_log_middleware.dart:11-22,382+`），代理路径不加策略就不会被记录，但也意味着**没有任何审计**。

### 5.3 上游事实回填（lead 核实，2026-10-29）【已验证：官方源码/Release】

- **版本/分发**：最新 release `v4.143.1`（2026-10-23，对应 Code 1.143.1）；standalone 包自带 Node，linux-amd64 约 230MB（压缩），Linux 要求 glibc ≥ 2.28；每个平台单独发包，**Windows-amd64 包自 v4.137.0 起随 release 发布**，但 docs/install.md 仍写「不发布 Windows 版本」，属文档滞后，需实测。证据：GitHub Releases API + `docs/install.md`。
- **子路径**：code-server 有正式 base-path patch（`patches/base-path.diff`，注释明确「domain.tld/my/base/path」），服务端用 `relativeRoot(req.originalUrl)` 生成相对根（`src/node/http.ts:163-167`），HTML 模板用 `{{BASE}}`/`{{CS_STATIC_BASE}}`。**代理应保留路径前缀转发**（`/ide/...` 原样给上游），不要剥离；`--abs-proxy-base-path` 只影响 `/absproxy/<port>` 应用代理，不是 IDE 自身前缀。
- **WS**：`wsRouter.ws(/.*/, ensureOrigin, ensureAuthenticated, ensureVSCodeLoaded, ...)`（`src/node/routes/vscode.ts:245`）即所有路径都可能升级，代理不能只转发某个固定 WS 路径。
- **健康检查/自退**：`GET /healthz` 返回 `{status,lastHeartbeat}`；`--idle-timeout-seconds` 可在无浏览器连接后自动退出（`docs/FAQ.md`）。
- **认证**：`--auth none|password`；`--auth none` 仅在 loopback/受信网络使用（官方 SSH 端口转发指南即如此）；密码登录限流（2 次/分钟 + 12 次/小时）。扩展市场用 Open VSX，不能接 Microsoft Marketplace（`docs/FAQ.md`）。

## 6. 缺口与风险清单

| # | 缺口/风险 | 证据 | 影响 |
|---|---|---|---|
| 1 | 无 `shelf_proxy` 等依赖，反代需手写或加依赖 | `pubspec.yaml:39-50`（shelf/shelf_router/shelf_static/shelf_web_socket/web_socket_channel/dartssh2） | 工作量集中在 WS/流式/错误映射 |
| 2 | 无多路复用隧道抽象，三份相似实现各自为政 | `port_forward_service.dart:134-182`、`docker_socket_tunnel_service.dart:161-194`、`secure_browser_tunnel_service.dart:139-148` | 建议抽 `LoopbackSshBridge` 共用 |
| 3 | 无子进程托管（无 PID/日志/重启） | `chrome_launcher.dart:141-151`、`ai_agent_pi_bridge.dart:116-120` | 本机 code-server 崩溃无自愈、日志丢失 |
| 4 | 退出清理链只停隧道，不杀子进程 | `server_container.dart:464-470` | 僵尸进程/端口占用 |
| 5 | 代理路径默认无鉴权、无审计 | `access_middleware.dart:10-13`、§5.10 | 等于公开 IDE，必须显式加固 |
| 6 | 端口转发监听无鉴权且 `bindHost` 可配 | `port_forward_rule.dart:29-32`、`port_forward_service.dart:73-79` | 用户配 0.0.0.0 即把 code-server 直接暴露 |
| 7 | SSH 空闲回收/静默检测会拆隧道 | `ssh_service.dart:487-538` | 需 attachLease + 心跳 |
| 8 | `lib/` 内 0 处 code-server 相关实现（`grep -i "code[-_ ]?server" lib/` 无命中，除本调研文档外） | — | 全新增模块，无历史包袱也无现成脚手架 |
| 9 | 上游事实（版本/base path/--auth/WS 路径/iframe 限制） | 已由 lead 用 shell curl 核实并回填 §5.3；distribution.md 记录分发细节 | 版本 v4.143.1；子路径方案可行但需 PoC |

## 7. 建议的最小落地顺序（供决策，不含实现）

1. 抽 `SshLoopbackBridge`（复用 docker 隧道形态）+ 单测（参照 `test/` 里 service 级测试的注入风格）。
2. 在 `server_handlers.dart:155-158` 加前缀分流中间件 + 自鉴权 + 拒绝 `Origin` 缺失的写请求。
3. `HttpClient` 反代 handler（HTTP 流式）+ `webSocketHandler` 桥接（WS）。
4. 进程侧先做「外部已装 code-server 的 URL/端口登记」（只读状态 + `BackendPortsService` 展示，`lib/server/features/settings/backend_ports_service.dart:24-84`），再做本机 spawn 托管。
5. 配置落库走 v22 迁移（`database_service.dart:566,604-606`），CLI/GUI 开关对齐 `--enable-secure-browser` 先例。


## 8. 决策收敛后的调整（2026-10-29）

目标锁定：IDE 只跑在 SSH 目标 Linux 主机（不实现本机 provider）、安装走离线包、支持多会话。

### 8.1 优先级变化

- §4.1 的“本机子进程托管”暂不实现；`Process.start` 相关缺口不再是本期阻塞项。
- 重点变为：远端安装/传输 + 会话生命周期 + 同源代理 + 离线包缓存。
- 具体模块、API、数据表、任务拆分见 [`remote-implementation-plan.md`](remote-implementation-plan.md)。

### 8.2 新增能力点

| 能力 | 落点 | 说明 |
| --- | --- | --- |
| 代理分流与鉴权 | `server_handlers.dart` Pipeline 层 | `/ide/<sessionId>/` 命中才处理；剥离子路径前缀；复用 `AccessAuthService.authenticate` |
| 会话注册表 | 新 `features/code_server/` | sessionId、connectionId、hostKey、远端 port/pid、bridgePort、状态；sqlite 新表（v22） |
| 远端安装 | 新 `RemoteIdeInstaller` | 预检 arch/glibc/磁盘/tar；解压到 `~/.local/lib/hostdeck/code-server/<ver>` |
| 离线包传输 | SSH 层 | 现有 `execWithResult` 的 `stdin` 是 String，**不能传二进制 tar.gz**；需新增 `execStream(Stream<List<int>>)`（`client.execute` 的 stdin sink 流式写入）或 SFTP 分块写 + 远端 sha256 校验 |
| 会话桥 | 抽自 Docker 隧道 | `127.0.0.1:0` 监听 → 每连接 `client.forwardLocal('127.0.0.1', remotePort)`；WS/HTTP 共用 |
| 租约 | `SshService.attachLease/touch` | 会话启动持有 `ide:<sessionId>` 租约；代理请求 touch；停止/断开释放 |
| 多会话存储 | code-server 启动参数 | `--enable-remote-storage`（v4.143.1 已支持）把工作台状态写远端 user-data-dir |

### 8.3 二进制/流式传输的硬约束

- 离线包 219MB（压缩），不能整体读入内存；上传接口也必须流式落盘（shelf_multipart 的流式能力需先验证，否则改用手写 multipart 解析或分块上传）。
- 远端解压优先流式：`client.execute('mkdir -p ... && tar -xz -C ...')` 后把文件流写入 `sshSession.stdin`；需要处理 SSH 窗口/背压与超时，失败清理 `.partial`。
- 若流式实现风险高，退化方案：SFTP 上传 tar.gz 到远端临时目录 → `sha256sum` 校验 → `tar -xzf` → 删除包；实现简单但多占一份 219MB 远端空间。
- 传输进度通过 SSE 上报（已读字节/总字节/阶段）。

### 8.4 远端进程管理

- 启动：`setsid nohup ... > log 2>&1 & echo $! > pid`；用 HostDeck 自己的 bridge 请求 `/healthz` 判定，不依赖远端 curl。
- 停止：`kill -TERM pid`，超时 `kill -KILL`；进程组/子进程需一并处理（code-server 会拉起 node 子进程，实际是同一进程树）。
- 远端 `sessions/<sessionId>.json` 记录 pid/port/version；HostDeck 重启后探测接管或清理，避免孤儿。
- 端口从 18090 起按 hostKey 哈希偏移，最多重试 10 次。
- logind `KillUserProcesses=yes` 会在 SSH 会话结束时杀掉进程；本方案默认“断开即停”，与之一致；若要跨断开保活，需 `loginctl enable-linger`（暂不支持）。

### 8.5 认证与 Origin 的补充

- 代理到 code-server 时重写 `Host` 和 `Origin` 为 `127.0.0.1:<port>`，否则 WS 的 `ensureOrigin` 会 403。
- HostDeck 侧 WS upgrade 必须做同源校验；`/ide/` 的所有静态资源请求也要鉴权（不要只保护入口 HTML）。
- `--auth none` 仅绑定 loopback；远端多用户主机上同机其他用户可达该端口，属已知风险（见主文档 §6/§7）。
