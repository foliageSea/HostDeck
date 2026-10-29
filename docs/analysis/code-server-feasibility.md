# HostDeck 集成 code-server 可行性分析

> 版本：2026-10-29｜范围：当前仓库（Dart shelf 后端 + Vue 3 WebOS 前端 + Electron 壳 + Docker/CLI 分发）
> 结论先行：**技术上可行，推荐「同源子路径反向代理 + 按需托管 code-server」**；iframe 直连端口不可行（上游返回 `X-Frame-Options: SAMEORIGIN`）。
> 配套材料：[`backend.md`](backend.md)（后端接入点）、[`frontend.md`](frontend.md)（前端承载点）、[`distribution.md`](distribution.md)（分发/部署）、[`poc-subpath-proxy.md`](poc-subpath-proxy.md)（实测记录）。
> 决策收敛（2026-10-29）：目标锁定 **SSH 目标 Linux 主机**、**离线安装包**、**多会话**；落地设计见 [`remote-implementation-plan.md`](code-server/remote-implementation-plan.md)。
> 展示方式调整（2026-10-29）：启动后直接在新标签页打开 IDE，不再使用内嵌 iframe；同源 /ide/ 反向代理仍然保留。

## 0. 结论摘要

1. **可行性**：code-server 官方支持子路径部署（`patches/base-path.diff`），且本地实测「剥离 `/ide` 前缀 → 上游根路径」的反代可完整加载 workbench HTML、5.4MB 的 `workbench.js`、CSS、manifest 与 WebSocket。HostDeck 现有 shelf 栈能复刻该代理（`request.hijack` + 原始 socket 桥接已跑通）。
2. **不可行的捷径**：把 iframe 直接指向 `http://host:<port>/`。code-server 默认返回 `X-Frame-Options: SAMEORIGIN`，端口不同即异源，浏览器会拒绝渲染；同时跨源还会遇到 HostDeck 登录 Cookie 不共享、HTTPS 混合内容、远端 B/S 场景下 loopback 不可达等问题。
3. **推荐形态（已按决策收敛）**：
   - IDE 固定运行在 **SSH 目标 Linux 主机**，经 SSH 隧道 + 同源反代内嵌，不实现本机 provider。
   - 安装走**离线包**：HostDeck 发布/管理员上传，经 SSH 推送到目标机，不依赖远端联网。
   - 支持**多会话**：每个 SSH 连接一个 IDE；`--enable-remote-storage` 把工作台状态持久化到各自远端，规避同源浏览器存储冲突。
4. **主要成本**：代理内核、离线包上传/传输/校验、远端安装升级、会话生命周期/租约、多会话隔离与性能；预计 **23～32 人日**。
5. **合规**：code-server 为 MIT；HostDeck 为 GPL-3.0-only，兼容。但只能使用 Open VSX 扩展市场，Microsoft Marketplace 与部分微软扩展（Copilot、Pylance 等）不可用，需在产品文案中明确。

## 1. 目标与判定标准

HostDeck 已有单文件 Monaco 编辑器（`host-deck-ui/src/views/TextEditor/index.vue`），但缺少工作区/文件树/多文件搜索/LSP/内置终端/Git/扩展。集成 code-server 的价值是补上「完整 IDE」。

判定标准（按重要性排序）：

| # | 标准 | 说明 |
| --- | --- | --- |
| 1 | 编辑的是目标文件系统 | 用户在 HostDeck 中 SSH 到哪台主机，IDE 就应编辑哪台主机的文件 |
| 2 | 单一登录态 | 复用 HostDeck 访问认证，不在 iframe 内二次登录 |
| 3 | 同源内嵌 | 桌面窗口内打开，不被 XFO/CSP/混合内容拦截 |
| 4 | 可运维 | 安装、启动、停止、健康检查、日志、升级、退出清理 |
| 5 | 跨形态 | Linux/macOS/Windows CLI、Electron、Docker、纯 B/S |
| 6 | 安全边界清晰 | IDE 等于远程代码执行能力，代理入口必须鉴权、审计、不可裸奔 |

## 2. 现状基线（仓库事实）

| 维度 | 现状 | 证据 |
| --- | --- | --- |
| HTTP 入口 | 唯一 shelf `Pipeline → Cascade`；SPA fallback 会把非 `api/` 的未知路径回 `index.html` | `lib/server/app/server_handlers.dart:76-159`，fallback `:95-109` |
| 鉴权 | `accessMiddleware` 只包 `api/`，非 `api/` 直接放行；Cookie `hostdeck_session`，`SameSite=Strict; Path=/; HttpOnly`，12h 内存会话 | `lib/server/features/access/access_middleware.dart:10-13`；`access_auth_service.dart:36,291-301` |
| WS | 全部挂 `/api/ws/*`（终端/监控/会话状态），`shelf_web_socket` + 20s ping | `lib/server/features/terminal/terminal_controller.dart:22-38` |
| 窗口体系 | 无 vue-router，全部是 WebOS 窗口；`:is` 动态渲染，props 无类型；已有通用 `iframe-app`（`hide:true`、1180×760、refresh action） | `host-deck-ui/packages/webos/src/vue/DesktopWindow.vue:376-379`；`host-deck-ui/src/lib/host-desktop-apps.ts:60-70`；`views/IframeApp/index.vue:42-50` |
| 端口转发 | 本地 TCP 监听 → 每个连接一条 SSH `direct-tcpip` → 字节中继；独立端口、无鉴权、可直接透传 WS | `lib/server/features/port_forwards/port_forward_service.dart:73-79,134-182` |
| Docker 隧道模板 | 本地 `127.0.0.1:0` 监听 + SSH channel + `HttpClient(autoUncompress=false)`，但无 WS | `lib/server/features/docker/docker_socket_tunnel_service.dart:99-127,161-194`；`docker_engine_repository.dart:68,265-317` |
| 安全浏览器 | SSH SOCKS5 + 独立 Chrome，非内嵌，依赖本机 Chrome | `secure_browser_tunnel_service.dart:139-148`；`chrome_launcher.dart:104-112` |
| 长驻进程 | **无**。只有一次性 `Process.start`（Chrome/pi bridge），无 PID/重启/日志托管 | `chrome_launcher.dart:141-151`；`ai_agent_pi_bridge.dart:54-64` |
| SSH 生命周期 | 空闲 120s 且无租约/无活动即断开；3 分钟无字节判死 | `lib/server/core/ssh/ssh_service.dart:409-416,487-538` |
| 现有 IDE 能力 | Monaco 单文件读写，无文件树/LSP/终端/Git | `host-deck-ui/src/views/TextEditor/index.vue`；`package.json` monaco 0.55.1 |

**由此得到三个硬约束**：

1. `/ide/` 必须自己鉴权（不能指望 `accessMiddleware`），并且要处理 WS 的同源校验。
2. 反代必须挂在 Pipeline 分流层，不能 `cascade.add` 到尾部——上游 404 会被 SPA fallback 吞成 `index.html`（`shelf-1.4.2/lib/src/cascade.dart:70-92`）。
3. 远端 IDE 的隧道必须持有 SSH 租约（`attachLease`）并在流量上 `touch`，否则几分钟后连接会被回收器拆掉。

## 3. code-server 上游事实与约束

| 项 | 事实 | 影响 |
| --- | --- | --- |
| 版本 | 最新 release `v4.143.1`（2026-10-23，对应 Code 1.143.1） | 需锁定版本并做升级冒烟 |
| 许可证 | MIT（VS Code 核心亦 MIT） | 与 GPL-3.0-only 兼容；若随镜像分发需补 `THIRD_PARTY_NOTICES` |
| 分发包 | standalone 自带 Node；linux-amd64 压缩 219MB，解压 **676MB**（实测） | 不适合塞进 Electron 安装包；按需下载/挂载 |
| 平台 | Linux amd64/arm64（glibc ≥ 2.28）、macOS amd64/arm64、**Windows-amd64 自 v4.137.0 起随 release 发布**（官方 `docs/install.md` 仍写不支持，文档滞后） | Windows 需实机验证；Alpine/musl 需 npm 或 Docker |
| 子路径 | 官方 `patches/base-path.diff` 支持 path-rewriting 反代；实测**必须剥离前缀** | `/ide/X` → 上游 `/X`，不能保留 |
| iframe | 默认 `X-Frame-Options: SAMEORIGIN` + CSP（`connect-src 'self' ws: wss:`） | 只能同源内嵌；跨源直连会被浏览器拦截 |
| WebSocket | 路由 `wsRouter.ws(/.*/)`，所有路径都可能升级；升级时校验 Origin 与 Host 一致 | 代理要转发任意 WS 路径，并重写 `Host/Origin`（或配 `--trusted-origins`） |
| 认证 | `--auth none|password`；`--auth none` 只适合 loopback/受信网络；密码登录限流 | 推荐 `none` + 仅 loopback/SSH + HostDeck 鉴权 |
| 运维 | `GET /healthz`、`--idle-timeout-seconds`、`--disable-telemetry`、`--disable-update-check` | 可直接用于健康检查/自退/关遥测 |
| 扩展 | 使用 Open VSX；不能接 Microsoft Marketplace | 部分扩展不可用，需在文档中说明 |
| 多用户 | 单实例单用户模型，不支持多租户 | 与 HostDeck 单管理员定位一致；多用户需一用户一实例 |
| 数据目录 | `--user-data-dir`、`--extensions-dir` 可重定向 | 放 HostDeck dataDir 或远端用户目录，便于备份/清理 |
| 多会话存储 | `--enable-remote-storage` 把工作台 settings/state 持久化到远端 user-data-dir（v4.143.1 已支持） | 多会话同源时避免共享浏览器 IndexedDB；初始化失败会回退浏览器存储 |

**PoC 关键结果**（详见 [`poc-subpath-proxy.md`](poc-subpath-proxy.md)）：

- 剥离前缀：`/ide/`、深度 JS（5.4MB）、CSS、manifest、`/ide/healthz` 全部 200；未知路径 404 正常透传。
- 保留前缀：全部 404（Express 路由挂在根）。
- WS：`request.hijack` + 重放握手头 + 原始 socket 双向 pipe，`/ide/healthz` 升级成功。
- gzip：必须 `autoUncompress=false` 并保留 `content-encoding`。

## 4. 方案对比

| 方案 | 编辑目标 | 认证 | 改造量 | 关键风险 | 结论 |
| --- | --- | --- | --- | --- | --- |
| A. iframe 直连端口（现有 `iframe-app`） | 取决于 code-server 所在机 | 无（code-server 自带密码/或 none） | 极小 | **XFO SAMEORIGIN 直接拦截**；第三方 Cookie；HTTPS 混合内容；远端 loopback 不可达 | **不可行**，不要采用 |
| B. 新标签 / SecureBrowser 打开 | 本机或经 SOCKS5 可达的远端 | code-server 自带 | 小 | 脱离应用窗口；登录态不共享；移动端/无 Chrome 不可用 | 仅作应急/降级入口 |
| C. 同源反代 + **本机托管** | HostDeck 所在机的文件系统 | HostDeck Cookie | 中 | 编辑的不是 SSH 目标；676MB 体积 | **不采用**（决策 1） |
| D. 同源反代 + **远端 SSH 托管** | SSH 目标 Linux 主机的文件系统 | HostDeck Cookie | 大 | 安装/端口/租约/升级/性能；glibc/musl/磁盘 | **唯一主方案**（决策 1/2） |
| E. 同源反代 + **外部已有实例** | 由用户决定 | 用户自管（可代理注入？） | 小～中 | 版本/URL/网络策略；SSRF/TLS 证书；跨域目标需白名单 | 仅作降级/运维入口 |
| F. 替代品：openvscode-server | 同 C/D | 无内置认证，靠反代 | 中 | 官方发布包仅 Linux（x64/arm64/armhf），无 macOS/Windows 包；生态小于 code-server | 备选；其 `--server-base-path` 原生支持子路径 |
| G. 替代品：VS Code Server (`code serve-web`) | 同 C/D | Microsoft 账号/令牌 | 中 | **许可证只允许微软授权场景**，不适合 HostDeck | 排除 |
| H. 自研 Monaco 工作区 | 需自建文件树/LSP/终端 | 已有 | 很大 | 3～6 个月，仍缺扩展/调试 | 不推荐作为 IDE 方案 |

**推荐组合（决策后）**：**D 为唯一内嵌主方案**；E 仅用于已有实例/应急；A 明确不做；B 仅降级；F 作为 code-server 不可用时的技术备选。

## 5. 推荐架构详设

### 5.1 组件与链路

```text
Browser (HostDeck SPA, 同源)
  ├─ 窗口 iframe: /ide/<sessionId>/?folder=/path
  │        │
  │        ▼
  └─ shelf Pipeline
       ├─ accessLog / sshActivity
       ├─ CodeServerProxyMiddleware   ← 新增：/ide/* 分流 + 鉴权
       │     ├─ HTTP:  HttpClient(autoUncompress=false) → 上游
       │     └─ WS:    request.hijack → 原始 socket ↔ 上游 socket
       │                 (剥离 /ide/<sessionId> 前缀，重写 Host/Origin)
       └─ Cascade(api → wallpapers → static → SPA)
                          │
              ┌───────────┴────────────┐
              ▼                        ▼
     本机 code-server          远端 code-server (SSH 目标)
     127.0.0.1:<port>          127.0.0.1:<port>
     由 IdeProcessManager      经 LoopbackSshBridge
     启动/停止/健康检查          (本地监听 → direct-tcpip)
```

### 5.2 代理层（核心模块）

建议新增 `lib/server/features/code_server/`：

| 文件 | 职责 |
| --- | --- |
| `code_server_controller.dart` | `/api/code-server/*` 状态、启动、停止、安装进度 |
| `code_server_session.dart` | 会话模型：id、connectionId、provider、上游 host:port、状态、错误 |
| `code_server_provider.dart` | 抽象：`ensureInstalled / start / stop / status / health` |
| `remote_ssh_provider.dart` | 远端预检/安装/启动/健康检查 + 隧道租约 |
| `ide_package_store.dart` | 离线包上传/校验/缓存/列表/删除 |
| `remote_ide_installer.dart` | 远端预检、传输、解压、版本校验、升级/回滚 |
| `ide_session_manager.dart` | 会话注册、端口分配、租约、恢复/清理 |
| `code_server_proxy.dart` | HTTP/WS 反代（独立可测，不依赖 controller） |
| `loopback_ssh_bridge.dart` | 抽自 Docker 隧道：本地 `127.0.0.1:0` → SSH channel |
| `routes/code_server_routes.dart` | 新增 API 路由注册 |

挂载方式（与 backend.md 方案 B 一致）：

```dart
return Pipeline()
    .addMiddleware(accessLogMiddleware(log))
    .addMiddleware(sshActivityMiddleware(sshService))
    .addMiddleware(codeServerProxyMiddleware(proxyService, accessService)) // 命中 ide/ 才处理
    .addHandler(cascade.handler);
```

**HTTP 代理要点**：

- 路径映射：`/ide/<sessionId>/...?q` → 上游 `/...?q`，**剥离前缀**；sessionId 可省略（v1 单会话）。
- 请求头：去掉 `host/connection/transfer-encoding/upgrade/keep-alive/accept-encoding/cookie/authorization`；`accept-encoding: gzip`。
- 响应：`autoUncompress=false`，透传状态码/头（保留 `content-encoding`），`Response(..., context: {'shelf.io.buffer_output': false})`；`content-length` 交给 shelf 重新计算。
- 超时：连接 10s、响应头 30s、整体 5min（IDE 长轮询/下载）；客户端断开时 `abort` 上游请求。
- 404 必须原样返回，不能被 SPA fallback 吞掉。
- **不要**剥离 `X-Frame-Options`（同源下无害；保留可防止被异源站点嵌）。

**WS 代理要点**：

- 命中 `Upgrade: websocket` 后 `request.hijack`；向上游 TCP 连接，重放请求行（剥离前缀）、`Host: 127.0.0.1:<port>`、`Origin: http://127.0.0.1:<port>`、`Sec-WebSocket-Key/Version/Protocol`。
- 双向 pipe，使用 `Stream.pipe` 保留背压；任一端关闭时关闭另一端；统计活动连接，停止会话时强制关闭。
- 不能按文本解码（终端 WS 的 `String` 假设不适用），必须字节级转发。
- HostDeck 侧鉴权：`AccessAuthService.authenticate(request)`；`authService.enabled && principal == null` → 401；WS 额外校验 `Origin` 与 `Host` 同源。
- 日志：`/ide/` 请求按采样或 debug 级别记录，避免 `accessLogMiddleware` 每请求 info 刷屏。

### 5.3 认证与安全

- **主认证**：复用 `hostdeck_session` Cookie（同源 iframe 会自动携带；`SameSite=Strict` 只拦跨站点，不拦同站不同路径）。
- **未登录**：代理返回 401（JSON 或极简 HTML），前端显示「登录已过期」并提供刷新；不要 302 到 SPA 根路径（iframe 内会嵌套整个应用）。
- **CSRF/WS 劫持**：WS upgrade 与写方法必须校验 `Origin` 与 `Host` 同源；无 Origin 的非浏览器客户端（CLI/测试）可放行或要求 Bearer。
- **code-server 侧**：`--auth none` + 仅绑定 loopback/SSH 通道；**绝不允许** `--bind-addr 0.0.0.0`。若需更强隔离，可改为随机密码 + 代理服务端登录并注入会话 Cookie（复杂度更高，P2 再评估）。
- **本地端口暴露**：桥接监听 `127.0.0.1:0`，多用户主机上其他本地用户仍可能扫到；可选加「握手首包 Token 校验」或 Unix socket（与 SSH streamlocal 配合）。第一版记录风险并在文档标注「单用户/受信主机」。
- **审计**：IDE 操作日志（启动/停止/安装/打开）写入操作日志；代理 HTTP 明细不落库，仅调试日志。
- **凭据**：不把 HostDeck Cookie/Authorization 转发给 code-server；不记录密码/token。

### 5.4 生命周期

> 决策收敛后：本机 provider 不实现，以下以**远端 provider**为准；本机段落仅保留作参考。

**远端 provider（唯一实现）**：

1. 探测：`command -v code-server`、`code-server --version`、`uname -m`、`ldd --version`（glibc）、磁盘/内存。
2. 安装：**离线包**（上传/发布资产）经 SFTP 或流式 exec 推送到 `~/.local/lib/hostdeck/code-server/<ver>`，校验 sha256 后解压；无 sudo；不依赖远端联网。
3. 启动：`setsid nohup ... > ~/.local/share/hostdeck/code-server/<hostKey>/logs/code-server.log 2>&1 & echo $! > .../sessions/<sessionId>.json`；参数含 `--auth none --enable-remote-storage --disable-telemetry --disable-update-check --user-data-dir ... --extensions-dir ...`；健康检查经 bridge 请求 `/healthz`（不依赖远端 curl）。
4. 端口：避开 HostDeck 自身端口（Electron server 默认 18080，`host-deck-electron/src/main/server-runtime.cjs:15-18`），建议从 `18090` 起或动态探测，启动前用 `ss -ltn`/重试确认占用。
5. 隧道：`LoopbackSshBridge` 绑定 `127.0.0.1:0`，每个本地连接 `client.forwardLocal('127.0.0.1', remotePort)`；HTTP 与 WS 共用。
6. 租约：会话启动时 `attachLease(connectionId, 'code-server:<sessionId>')`，每次代理请求 `touch(connectionId)`；停止/WS 全关时 `detachLease`。
7. 断开：SSH 断开自动停隧道；尽力 kill 远端进程，兜底 `--idle-timeout-seconds=1800`；重启 HostDeck 通过 sessions/*.json + `/healthz` 接管或清理。

### 5.5 配置与数据

- CLI：`--code-server-offline-dir`（只读离线包目录）、`--code-server-version`、`--code-server-max-sessions`、`--code-server-idle-timeout`。
- 持久化：设置表/JSON（UI 可改），参考 `--enable-secure-browser` 的先例（`server_cli.dart:41-44,70-79`）；若落库需 schema v22（当前 v21，`database_service.dart:566,604-606`）。
- 数据目录：HostDeck 端 `<dataDir>/code-server/{packages,offline}`；远端 `~/.local/lib/hostdeck/code-server/<version>` 与 `~/.local/share/hostdeck/code-server/<hostKey>/{data,extensions,logs,sessions}`。
- 升级：固定版本 + sha256；升级前备份 `extensions`/配置；禁止 code-server 自更新（`--disable-update-check`）。
- 清理：删除版本目录、停止进程、清理端口/PID；提供「卸载 IDE 数据」入口。

### 5.6 API 草案（走统一 `Result`）

| Method | Path | 说明 |
| --- | --- | --- |
| GET | `/api/code-server/packages` | 离线包列表（版本/arch/sha256/大小） |
| POST | `/api/code-server/packages` | 上传离线包（流式 multipart，返回 taskId） |
| DELETE | `/api/code-server/packages/<id>` | 删除离线包 |
| POST | `/api/code-server/packages/scan` | 扫描离线目录并导入 |
| GET | `/api/code-server/targets/<connectionId>/status` | 预检/安装/会话状态 |
| POST | `/api/code-server/targets/<connectionId>/install` | 安装指定离线包 |
| POST | `/api/code-server/targets/<connectionId>/start` | 启动（folder） |
| POST | `/api/code-server/targets/<connectionId>/stop` | 停止并释放隧道/租约 |
| GET | `/api/code-server/targets/<connectionId>/events` | SSE 安装/启动进度 |
| GET | `/api/code-server/logs?tail=` | 最近日志（脱敏） |
| GET | `/ide/<sessionId>/...` | 反向代理（**非** `/api`，自行鉴权） |

### 5.7 前端接入

1. 新增 `DesktopAppId = 'code-server'` 与 `CodeServerView`（可组合 `IframeApp`）：加载中、未安装、启动中、错误、重试、外部打开、全屏。
2. `iframe` 增加 `allow="clipboard-read; clipboard-write; fullscreen"`；**不要**加 `sandbox`（VS Code workbench 需要同源能力）。
3. URL 使用相对路径 `/ide/<sessionId>/?folder=<encodeURIComponent(path)>`（code-server 支持 `folder`/`workspace` 查询参数）。
4. 入口：Dock/启动台；文件管理器工具栏/右键「在 IDE 中打开」；终端工具栏；后续 Docker 卷/目录。
5. 关闭窗口时默认 stop（远端）并释放租约；可在设置中改为保留运行；刷新用现有 `refreshToken` 机制。
6. 开发态：`host-deck-ui/vite.config.ts` 增加 `/ide` 代理（`ws: true`）到 8080，否则 `pnpm dev` 下 iframe 404。

### 5.8 部署形态（决策后）

| 形态 | 远端 SSH IDE | 说明 |
| --- | --- | --- |
| HostDeck on Linux/macOS/Windows（CLI 或 Electron） | ✅ | HostDeck 所在 OS 无关，只要求能 SSH 到 Linux 目标 |
| Docker（HostDeck 容器） | ✅ | 离线包放 `/data/code-server/packages` 或镜像内置；sidecar 仅适合共享卷场景 |
| 纯 B/S 远端访问 | ✅ 核心场景 | 必须同源反代；外网 TLS 反代需转发 `/ide/`（含 WS） |
| 本机开发（不 SSH） | ❌ 不支持 | 决策 1：只编辑 SSH 目标主机 |

外网 nginx 需追加：`location /ide/ { proxy_pass http://hostdeck:8080; proxy_http_version 1.1; proxy_set_header Upgrade $http_upgrade; proxy_set_header Connection "upgrade"; proxy_buffering off; proxy_read_timeout 3600s; }`，并确保 `client_max_body_size` 足够（离线包/上传）。

## 6. 风险与缓解

| # | 风险 | 级别 | 缓解 |
| --- | --- | --- | --- |
| 1 | `/ide` 未鉴权 = 公开 RCE 入口 | 高 | 代理层强制 `AccessAuthService.authenticate`；WS 同源校验；安全测试用例 |
| 2 | iframe 被 XFO/CSP 拦截 | 高 | 已实测：同源反代可解；禁止直连端口 |
| 3 | SSH 空闲回收拆隧道 | 高 | `attachLease` + 请求 `touch`；断线自动清理 |
| 4 | SSH 通道数量/吞吐不足（IDE 资源请求多） | 中高 | 本地 bridge 复用 TCP 连接；限制并发；压测首屏（目标 LAN < 5s） |
| 5 | 676MB 解压 + 0.5～1GB 内存 | 中高 | 按需安装到远端、显示资源占用、会话上限与告警 |
| 6 | 目标 Linux 的 glibc/musl/旧发行版不兼容 | 中高 | 预检 glibc ≥ 2.28 与架构；Alpine/CentOS 7 明确不支持并给出替代方案 |
| 7 | 多会话同源共享浏览器存储 | 中 | 启用 `--enable-remote-storage`；固定同一 code-server 版本；浏览器实测确认 |
| 8 | code-server 升级破坏子路径/接口 | 中 | 锁版本 + 冒烟测试（首屏/WS/终端/扩展） |
| 9 | Open VSX 扩展缺失 | 中 | 产品说明；支持手动 VSIX 安装 |
| 10 | 代理日志刷屏/性能 | 中 | `/ide` 日志降级/采样；流式响应不缓冲 |
| 11 | 离线包供应链/传输风险 | 中 | 发布资产 sha256 + 清单；上传校验；固定版本；禁用自更新 |
| 12 | 本地 bridge 端口被同机其他用户访问 | 中 | loopback + 随机端口 + 可选首包 Token/Unix socket；文档标注威胁模型 |
| 13 | 数据/扩展无限增长 | 低中 | 目录配额提示、清理入口、日志轮转 |
| 14 | 219MB 离线包上传/推送失败或远端磁盘不足 | 中 | 预检磁盘、分块/续传、失败清理、SSE 进度 |
| 15 | 许可证/第三方声明 | 低 | MIT 文本、THIRD_PARTY_NOTICES、镜像内保留 LICENSE |

## 7. 分阶段落地计划（决策后：远端优先、离线包、多会话）

以 1 名熟悉 Dart/Vue 的工程师估算，含测试与文档，不含 UI 设计评审。

| 阶段 | 内容 | 交付 | 工作量 |
| --- | --- | --- | --- |
| P0（本次） | 可行性分析 + 子路径/WS PoC | 本目录报告 + 实测记录 | 已完成 |
| P1 | 代理内核：`/ide/<sessionId>/` 分流、鉴权、剥离前缀、HTTP/WS、超时/日志、单测 | 可加载远端或外部 code-server | 4～6 人日 |
| P2 | 离线包：包格式/清单、上传/校验/缓存/列表/删除、扫描目录 | 管理端可上传并选择离线包 | 3～4 人日 |
| P3 | 远端安装：预检、SFTP/流式传输、解压、版本校验、升级/回滚、SSE | 目标机离线安装 | 5～7 人日 |
| P4 | 会话：启动/停止/健康、端口、租约、bridge、恢复、会话上限 | 单会话闭环 | 4～5 人日 |
| P5 | 多会话与前端：IDE 窗口、包管理页、状态/错误 UI、多窗口入口 | 多目标并行 IDE | 4～5 人日 |
| P6 | 硬化：安全、性能压测、Docker/文档、发布离线资产 | 可发布 | 4～6 人日 |

**合计 23～32 人日**。可先交付 P1～P4 的最小闭环（无外网目标机安装 + 打开 IDE + 关闭清理），约 15～20 人日；P5 再加多会话与包管理 UI。

**验收门槛（摘要）**：

- 目标机无外网、未装 code-server，上传离线包后完成安装并打开 IDE。
- 两台 Linux 目标同时打开 IDE，互不覆盖状态；未登录访问 `/ide/` 返回 401；跨站 WS 被拒。
- 关闭窗口/SSH 断开后进程、端口、租约释放；HostDeck 重启可接管或清理。
- 首屏在局域网 SSH 链路上 ≤ 5s；扩展、内置终端、文件保存可用。

## 8. 已确认决策与遗留问题

**已确认**：

| # | 决策 |
| --- | --- |
| 1 | IDE 编辑 SSH 目标主机，不实现本机 provider |
| 2 | SSH 目标全部为 Linux，仅适配 linux-amd64/arm64 |
| 3 | 提供离线安装包，不依赖远端联网 |
| 4 | 支持多 IDE 会话（每个 SSH 连接一个） |

**遗留问题**：

1. 远端多用户主机是否必须防同机其他用户访问 IDE？若是，需加随机密码或 Unix socket 方案。
2. 最大并发会话数（默认 4）与单目标内存告警阈值。
3. 离线包是否需要签名（除 sha256 外）与自动更新策略。
4. code-server 版本策略：全局固定一个版本，还是允许按目标机选择（影响 Service Worker 冲突）。
5. 完全离线时是否需要 VSIX 离线安装扩展。

## 附录 A：证据索引

- 后端接入点：[backend.md](backend.md)（服务组装、鉴权、隧道、进程、反代注意点）
- 分发与部署：[distribution.md](distribution.md)（Docker/Electron/Windows CLI、三类拓扑、体积与合规）
- 前端承载点：[frontend.md](frontend.md)（窗口体系、iframe、SecureBrowser、Electron、认证）
- 子路径反代实测：[poc-subpath-proxy.md](poc-subpath-proxy.md)
- 决策后实施方案：[remote-implementation-plan.md](code-server/remote-implementation-plan.md)
- 关键源码：
  - [`server_handlers.dart`](../../lib/server/app/server_handlers.dart)（Pipeline/Cascade/SPA）
  - [`access_middleware.dart`](../../lib/server/features/access/access_middleware.dart)（鉴权范围/Origin）
  - [`port_forward_service.dart`](../../lib/server/features/port_forwards/port_forward_service.dart)（TCP↔SSH 中继）
  - [`ssh_service.dart`](../../lib/server/core/ssh/ssh_service.dart)（租约/回收）
  - [`host-desktop-apps.ts`](../../host-deck-ui/src/lib/host-desktop-apps.ts)（应用注册）
  - [`IframeApp/index.vue`](../../host-deck-ui/src/views/IframeApp/index.vue)（iframe 承载）
- 上游：
  - code-server 源码 `src/node/http.ts`（relativeRoot/Origin 校验）、`src/node/routes/vscode.ts`（WS catch-all）、`patches/base-path.diff`
  - GitHub Releases v4.143.1（体积/平台资产）

## 附录 B：已验证 / 待验证

**已验证**：子路径剥离反代 HTTP/WS/静态资源/404；XFO SAMEORIGIN 行为；gzip 透传；standalone 体积；Linux glibc 要求；`--enable-remote-storage` 标志存在；Open VSX 配置。

**待验证**：完整 workbench 在真实浏览器中的加载/扩展/终端/webview；多会话 `--enable-remote-storage` 隔离与 Service Worker 行为；SSH 隧道下首屏性能；离线包 SFTP/流式传输吞吐；HTTPS+Secure Cookie 全链路。
