# 前端承载 code-server 的接入点调研

> 范围：`host-deck-ui/`（Vue 3 + WebOS 桌面窗口）、`host-deck-electron/`（Electron 壳层）。只读调研，未改业务代码。
> 证据格式为 `仓库相对路径:行号`；每条结论标注【事实】或【推测】。
> 仓库现状：全仓检索 `code-server|codeserver|openvscode|theia` 无命中，属全新接入。

## 结论摘要

1. 【事实】前端没有 vue-router（`host-deck-ui/package.json` 无该依赖，`host-deck-ui/src/router/` 不存在；`docs/frontend.md:23` 的"src/router/index.ts"已过时）。所有业务界面都是 WebOS 桌面窗口，由 `DesktopWindow` 用 `:is` 动态渲染并通过 `v-bind` 透传 props（`host-deck-ui/packages/webos/src/vue/DesktopWindow.vue:376-379`）。
2. 【事实】已有通用内嵌窗口 `iframe-app`：URL 完全由调用方 `openWindow('iframe-app', { url })` 传入，iframe 无 `sandbox`，仅 `allow="clipboard-read; clipboard-write"`（`host-deck-ui/src/views/IframeApp/index.vue:42-50`）。
3. 【事实】"端口转发"视图本身不打开页面，只复制监听地址（`host-deck-ui/src/views/PortForward/index.vue:390-393`）；真正打开被转发端口的是 Docker 视图与终端超链接，均用 `window.open(..., '_blank')` 交给外部浏览器（`host-deck-ui/src/views/Docker/hooks/useDockerView.ts:285-293`、`host-deck-ui/src/views/Terminal/hooks/useTerminalSession.ts:422-427`）。
4. 【事实】secure browser 不是内嵌方案，而是"SSH 动态转发(SOCKS5) + 独立 Chrome 实例"（`lib/server/features/port_forwards/secure_browser_tunnel_service.dart:139-148`、`host-deck-electron/src/main/chrome-launcher.cjs:103-111`）。
5. 【事实】改动最小的承载路径是"同源子路径反向代理 + 复用 HostDeck 登录 Cookie + `iframe-app`"；但后端鉴权只包 `api/` 路由，静态与 SPA 不受保护（`lib/server/app/server_handlers.dart:139-158`），新增子路径必须自行鉴权。

## 1 窗口体系（DesktopAppId / AppConfig / openWindow）

【事实】
- 应用 id 联合类型：`host-deck-ui/src/types/desktop.ts:22-48`（现有 26 个 id，无 IDE 类应用）。
- 应用注册表：`host-deck-ui/src/lib/host-desktop-apps.ts:46` `createHostDesktopApps()`；会话窗口上限 `maxSessionWindows = 8` 且只约束 `terminal`（同文件 `:29-30`）。
- `AppConfig` 字段：`host-deck-ui/packages/webos/src/core/types.ts:3-20`（`hide`、`showInLaunchpad`、`singleInstance`、`defaultProps`、`actions` 等）。
- 窗口标题取 `props.title`（`packages/webos/src/core/desktop.ts:141`），props 合并 `defaultProps`（同文件 `:134-135`），因此所有窗口 props 都是 `Record<string, unknown>`，无类型校验。
- store 门面：`host-deck-ui/src/stores/desktop.ts:345-356` 的 `openWindow(appId, props, options)`，只额外拦截 `logout`。
- `iframe-app` 为 `hide: true`（不出现在启动台/坞），尺寸 1180x760（`host-deck-ui/src/lib/host-desktop-apps.ts:60-70`），并挂了一个 `refresh` 动作（`host-deck-ui/src/stores/desktop.ts:141-143`）。

改造点（新增 IDE/代码服务器窗口）：
1. `types/desktop.ts` 增 `'code-server'`（id + AppIconKey）。
2. `lib/host-desktop-apps.ts` 增应用配置（复用 `IframeAppView` 或新建 `CodeServerView` 包装）。
3. `lib/app-icons.ts:29` 附近补图标映射（`iframe-app` 目前用 `fallbackAppIconUrl`）。
4. 若要单例/多实例、刷新动作，参考 `store.desktop.ts:141-143` 的 actions 注入方式。

## 2 IframeApp 的实现与限制

【事实】
- props：`url`、`title`、`refreshToken`（`host-deck-ui/src/views/IframeApp/index.vue:5-9`）；`refreshToken` 变化时自增 `key` 强制重建 iframe（`:16-26`）。
- `<iframe :src="url" allow="clipboard-read; clipboard-write" @load="isLoaded = true" />`，无 `sandbox`、无 `referrerpolicy`、无 URL scheme 校验（`:42-50`）。加载中显示"正在打开 xxx ..."遮罩（`:34-40`）。
- 唯一的调用代码在终端：启动命令执行后延迟打开（`host-deck-ui/src/views/Terminal/hooks/useTerminalSession.ts:331-350`，`openIframeAfterMs` 默认 2000）。但 `openIframeUrl` 除该 hook 与 `views/Terminal/index.vue:24` 的 props 声明外全仓无传参方，**该路径实际未被使用**（`openWindow` 传 `{title,url}` 的代码在 `:339-346`）。

【推测/限制】
- 若 iframe 指向 `http://<远端IP>:<端口>`（Docker 视图那种 URL），HostDeck 的 Cookie 不会带上；HostDeck 若以 https 提供服务，跨源 http iframe 还可能触发混合内容拦截（Chrome 对 `127.0.0.1`/`localhost` 有豁免，需实测）。
- 无 `sandbox` 意味着内嵌页面可 `top.location` 跳转、可 `window.parent` 访问（同源时完全同权）；内嵌 code-server 时为预期行为，但需注意 XSS 影响面扩大到宿主窗口。

## 3 端口转发视图如何"打开"被转发端口

【事实】
- 视图职责：CRUD + 启停 + VueFlow 拓扑图；本地地址由 `localAddress()` 拼出，`bindHost` 为 `0.0.0.0`/`::` 时替换成 `window.location.hostname`（`host-deck-ui/src/views/PortForward/index.vue:245-249`），只有"复制地址"按钮（`:390-393`、`:555-562`）。
- API 合约：`GET/POST /api/port-forwards`、`/:id/start|stop|DELETE|PUT`（`host-deck-ui/src/api/port-forward.ts:27-58`），全部走 `@/lib/http`。
- Docker 容器端口：URL 直接拼 `http://<sshHost>:<hostPort>`，用 `window.open` 开新标签（`useDockerView.ts:274-293`），不经过 HostDeck 源。
- 桌面钉住的端口链接：`openPinnedPortLink` 也是 `window.open(link.url, '_blank', 'noopener')`（`host-deck-ui/src/stores/desktop.ts:337-340`）；生产方只有 Docker 视图的 `togglePortLinkPin`（`useDockerView.ts:300-309`）。
- 【事实】`PortForward` 规则与"打开页面"之间当前没有任何连线，browser/iframe/secure-browser 三种打开方式都未接入该视图。

## 4 SecureBrowser 与 iframe 内嵌的差异

【事实】
- 前端：创建隧道 `POST /api/secure-browser-tunnels`（`host-deck-ui/src/api/secure-browser.ts:21-25`），然后用 `window.hostDeck.app.openInSecureChrome({ profileId, proxyPort })` 启动（`host-deck-ui/src/views/SecureBrowser/index.vue:78-92`）；无 Electron 时回退 CLI `launch`（`api/secure-browser.ts:36-42`）。能力探测：`/capabilities` → `launchEnabled/chromeDetected`（`secure_browser_tunnel_controller.dart:25-26`），CLI 需 `--enable-secure-browser`（`lib/server/app/server_cli.dart:41`、`:102`）。
- 后端：隧道 = `client.forwardDynamic(bindHost: '127.0.0.1', maxConnections: 128)`，即 SSH 动态转发/SOCKS5（`secure_browser_tunnel_service.dart:61-86`、`:139-148`），一个连接只保留一条隧道（`:43-47`）。
- 壳层：Electron 用 `--user-data-dir=<userData>/secure-browser-profiles/<profileId>` + `--proxy-server=socks5://127.0.0.1:<bindPort>` + `--proxy-bypass-list=<-loopback>` 拉起本机 Chrome（`host-deck-electron/src/main/chrome-launcher.cjs:97-111`）；后端 CLI 路径同构（`lib/server/features/port_forwards/chrome_launcher.dart:106`）。

差异结论：
| 维度 | iframe 内嵌 | SecureBrowser |
| --- | --- | --- |
| 渲染位置 | HostDeck 窗口内（WebOS） | 本机独立 Chrome 窗口（脱离应用） |
| 网络路径 | 浏览器直连 URL（跨源/CORS/Cookie 受限） | SSH SOCKS5 动态转发，可访问远端内网 |
| 依赖 | 无 | 本机必须装 Chrome（`chrome-launcher.cjs:38-63`） |
| 登录态 | 与 HostDeck 同源则可共享 Cookie | 独立 profile，完全不共享 |
| Electron | 直接可用 | 需 IPC `app:open-in-secure-chrome`（`host-deck-electron/src/main/ipc.cjs:51-54`） |

## 5 认证与 iframe

【事实】
- 登录态：`hostdeck_session` Cookie，`Path=/; HttpOnly; SameSite=Strict; Max-Age=12h`（`lib/server/features/access/access_auth_service.dart:36`、`:291-301`、`:58`）；前端 axios 带 `withCredentials: true`（`host-deck-ui/src/lib/http.ts:10-13`）。
- 鉴权中间件只挂在 `apiRoutes.router` 上（`lib/server/app/server_handlers.dart:143`），且中间件内部第一件事是"非 `api/` 直接放行"（`lib/server/features/access/access_middleware.dart:10-13`）；静态资源与 SPA fallback 在 cascade 中位于其后且无鉴权（`server_handlers.dart:149-158`）。因此**前端 SPA 本身是公开可取的**，安全边界实际是 `/api`。
- Origin 校验只对 `api/ws/*` 与 POST/PUT/PATCH/DELETE、且仅 `browserSession` 身份生效，要求 `Origin` 的 authority 完全等于 `Host`（`access_middleware.dart:34-46`、`:57-63`、`:65-78`）。
- 未设置任何 `X-Frame-Options` / CSP / `frame-ancestors`（全仓 grep 无命中），HostDeck 自身可被嵌入，反向代理 code-server 时也无需为此额外放开。

iframe 语义分析（SameSite=Strict）：
- 【推测】iframe 与顶层同源（`https://host/ide/`）时属同站请求，`hostdeck_session` 正常带上；跨源（`http://127.0.0.1:3000`）时 HostDeck Cookie 本就不该发往该源，Strict 不额外制造问题，但 code-server 自身 Cookie 会变成第三方 Cookie，Chrome 的第三方 Cookie 限制下可能被拒。
- 【事实】code-server 若挂在 `/api/...` 之外，鉴权必须由代理层自己补（现有中间件不会覆盖）；若强行挂在 `api/` 下，其资源请求将以 `browserSession` 身份受 Origin/SameSite 双重约束。

可选衔接方案：
- A（推荐）：同源子路径 `/ide/` 反向代理 + 在代理层复用 `AccessAuthService.authenticate(request)`，失败返回登录页/401；iframe 直接用相对路径。
- B：端口转发/隧道 + SecureBrowser（真实浏览器，code-server 自带密码或 `--auth none` 由代理鉴权）。
- C：端口转发 + iframe 直连 `http://host:port`（跨源，最省事但无登录态共享、可能混合内容/第三方 Cookie 问题）。
- D：一次性票据（代理在跳转 URL 注入短时 token，code-server 侧换取会话）——仓库内无现成机制，需新增。

## 6 TextEditor 能力边界 vs code-server

【事实】
- Monaco 编辑器（`host-deck-ui/package.json:44` `monaco-editor ^0.55.1`），`components/editor/CodeEditor.vue:1-30` 动态 `import('monaco-editor')`，支持 `readonly`、语言高亮、json/yaml 格式化。
- 窗口 props 只有 `connectionId`、`path`、`windowId`（`host-deck-ui/src/views/TextEditor/index.vue:12-16`）；读/写整文件走 `filesApi.readFile/writeFile`（`:243`、`:261`）。
- 语言映射见 `languageByFilename`/`languageByExtension`（同文件 `:80-149`），判定入口 `detectLanguage`（`:151-179`），快捷键 Ctrl/Cmd+S、Alt+Shift+F（`:33-34`）。
- 应用配置 `hide: true`、`singleInstance: false`（`lib/host-desktop-apps.ts:292-304`），从文件管理器打开。

边界：单文件读写、无文件树、无搜索替换跨文件、无 LSP/补全服务端、无终端、无 git、无扩展。code-server 提供完整 VS Code 工作台（工作区、终端、扩展市场），二者是"单文件编辑"与"完整 IDE"的定位差，不宜互相替代。

## 7 Electron / Flutter 壳层承载能力

【事实：Electron】
- 结构：`BrowserWindow`（只加载 tab 栏壳页面）+ 每个 Tab 一个 `WebContentsView`（`host-deck-electron/src/main/index.cjs:219-233`、`src/main/tab-manager.cjs:152-163`）。
- Tab 的 `webPreferences`：`contextIsolation: true`、`nodeIntegration: false`、`sandbox: true`、preload `host-deck.cjs`（`tab-manager.cjs:156-163`、`index.cjs:60`）。
- 新窗口一律外置：`setWindowOpenHandler` → `shell.openExternal`（`tab-manager.cjs:175-178`）。
- 全仓无 `webviewTag`、`<webview>`、`BrowserView`（grep 只命中 `WebContentsView`），即当前**没有通用的内嵌第三方站点入口**。
- `createTab(url)` 本身支持传 URL（`tab-manager.cjs:152`），但 IPC `tabs:create` 不接收参数、只用应用自身 URL（`src/main/ipc.cjs:91`；preload `src/preload/tabs.cjs:5`；UI 侧 `TabsShell.vue:312` `api.create()`）。
- 对外能力白名单：`window.hostDeck.app.*`（openInBrowser / openInSecureChrome / openDevTools / forceReload / clearBrowserCache / externalAccess）与 `window.hostDeck.window.*`（`src/preload/host-deck.cjs:3-26`）。

【事实：Flutter】
- `pubspec.yaml` 无任何 webview 插件（grep `webview|inappwebview|desktop_webview` 无命中）；`lib/main.dart:61-63` 只拼出 `http://localhost:5178`（debug）/`http://localhost:<port>`（release）字符串，真正的打开动作是 `launchUrl(uri, mode: LaunchMode.externalApplication)`（`lib/main.dart:154`，依赖 `pubspec.yaml:51` `url_launcher`）。
- 即：AGENTS.md 中"Flutter debug 的 WebView 加载 localhost:5178"与现状不符，Flutter 壳只能把地址交给系统浏览器，不构成 code-server 承载点。

## 8 可复用组件 / 改造点清单

| 目标 | 可复用 | 需要改动 |
| --- | --- | --- |
| 窗口内嵌 code-server（同源代理） | `IframeApp`（`views/IframeApp/index.vue`）+ `openWindow` | 新增 `DesktopAppId`、AppConfig、图标；URL 由代理地址生成 |
| 浏览器内打开（真实 Chrome，跨远端） | `PortForward` 规则 + `SecureBrowser` 隧道 | PortForward 节点增加"打开"入口；`secureBrowserApi.launch` 支持 `url` 参数（后端已接受，前端 API 已预留 `api/secure-browser.ts:36-42`） |
| 外部浏览器新标签 | `window.open(url,'_blank','noopener')` 既有范式 | 仅接一个按钮 |
| Electron 原生 Tab 打开 code-server | `createTab(url)` 已支持 URL | `ipc.cjs:91` 传参 + preload/UI 增加入口；并决定是否放开外部 URL（安全风险） |
| 认证衔接 | `AccessAuthService.authenticate`（Cookie 解析，`access_auth_service.dart:273-289`） | 代理路由需自己调用；或走 A 方案的子路径中间件 |

## 9 风险与缺口

1. 【事实】静态资源/SPA 无鉴权：任何 `/ide/` 子路径若不显式加鉴权即等同公开服务（`access_middleware.dart:10-13`）。
2. 【事实】无 CSP/X-Frame-Options：若上游（code-server 或其反代）返回 `X-Frame-Options` 或 CSP `frame-ancestors`，iframe 会被浏览器拒绝，代理层需剥离/重写响应头；code-server 默认响应头需实测（后端是否有头剥离能力属 task-1 结论）。
3. 【推测】Electron 内 Tab 与外链策略：`setWindowOpenHandler` 全量外置，code-server 里 `target=_blank` 的链接会弹到系统浏览器；如需留在应用内需新增标签页路由。
4. 【推测】第三方 Cookie 收紧（Chrome）会影响"跨源 iframe 直连 code-server 自身 Cookie"的可用性，A 方案（同源子路径）天然规避。
5. 【事实】`openPinnedPortLink`/`pinPortLinkToDesktop` 只在 Docker 场景有生产者，PortForward 视图未接入；"端口→页面"链路需新写。
6. 【事实】文档漂移：`docs/frontend.md:23` 仍描述 vue-router；`docs/modules/desktop-shell.md:22` 称应用配置在 `stores/desktop.ts`，实际在 `lib/host-desktop-apps.ts:46`。

## 10 待验证（交给后续实测）

- iframe 指向 `http://127.0.0.1:<port>` / `http://<远端IP>:<port>` 在 https 部署下的混合内容与 PNA 行为。
- Electron `WebContentsView` 内 iframe 的 `preload` 注入行为（当前未设置 `nodeIntegrationInSubFrames`，据 Electron 文档该选项默认 false 时 preload 不进入子 frame，需实测确认）。
- code-server 前端对 `base path`、Service Worker、WebSocket 子路径的硬编码程度（决定反代可行性细节）。

## 11 lead 回填：上游 code-server 事实（2026-10-29）

- **base path 可行**：code-server 维护 `patches/base-path.diff`，明确支持 `domain.tld/my/base/path`；服务端按 `req.originalUrl` 计算相对根（`src/node/http.ts:163-167`）。代理保留 `/ide/` 前缀转发即可，**不要剥离前缀**；`--abs-proxy-base-path` 只用于 `/absproxy/<port>`，与 IDE 自身前缀无关。
- **iframe 可嵌**：code-server 源码中未设置 `X-Frame-Options`/CSP `frame-ancestors`（无 helmet），默认允许被 iframe 嵌入；若未来版本加上，代理需剥离该响应头。
- **WS 需精确处理**：code-server 用 `wsRouter.ws(/.*/)`（`src/node/routes/vscode.ts:245`），任何路径都可能升级；且 `ensureOrigin` 要求 Origin 与 Host 一致（`src/node/http.ts:383-426`），同源代理必须重写 Origin/Host 或设置 `--trusted-origins`。
- **登录态**：推荐 `--auth none` + 仅 loopback/SSH 通道 + HostDeck 自身 Cookie 鉴权，可避免在 iframe 内做第二次登录；独立 Chrome（SecureBrowser）方案则保留 code-server 自带密码登录。


## 12. 决策收敛后的前端改造（2026-10-29）

已确认：IDE 只连接 SSH 目标 Linux 主机、离线包、多会话。

### 12.1 窗口与应用

- 新增 `DesktopAppId = 'code-server'`，`CodeServerView` 包装 `IframeApp`：加载、预检、安装、启动、错误、重试、停止、外部打开。
- 每个 SSH 连接一个 IDE 会话；同一目标再次打开时复用已有窗口（按 `connectionId` 查 `desktopStore.windows` 的 props）。窗口标题用 `user@host`，便于区分多会话。
- iframe URL 使用相对路径：`/ide/<sessionId>/?folder=<encodeURIComponent(folder)>`；`allow="clipboard-read; clipboard-write; fullscreen"`；不加 `sandbox`。
- 关闭窗口时按配置停止会话（默认停止远端进程并释放租约）；提供“保持运行”选项。

### 12.2 设置页 / 离线包管理

- 新增“IDE（code-server）”设置分区：离线包列表（版本、arch、大小、sha256、上传时间）、上传、扫描目录、删除、磁盘占用。
- 上传使用 `multipart/form-data` + 进度（XHR/Axios onUploadProgress）；大文件（219MB）显示速率/剩余时间，失败可重试。
- 目标机状态卡片：未连接 / 未安装 / 已安装版本 / 运行中 / 错误；显示预检结果（arch、glibc、磁盘）。
- 安装/启动进度用 SSE（`EventSource`），参考 `src/api/runtime-sessions` 的用法；SSE 不走统一 Result 解包。

### 12.3 API 客户端

- 新增 `src/api/code-server.ts`：packages 列表/上传/删除/扫描、target status、install、start、stop、events。
- 上传接口不要走 `src/lib/http.ts` 的默认 JSON 拦截器（非统一响应），单独配置 `responseType`/进度或使用原生 XHR。

### 12.4 入口与交互

- 文件管理工具栏/右键：在当前目录“用 IDE 打开”；终端工具栏：当前 SSH 会话打开 IDE。
- 启动台/Dock 增加 IDE 图标；未连接 SSH 时禁用并提示。
- 未登录/会话过期：代理返回 401，视图显示“登录已过期”，点击刷新（避免 iframe 内嵌整个 SPA）。
- 多会话资源提示：同时运行 N 个会话时显示远端内存占用，可配置上限。

### 12.5 Electron / 开发态

- Electron 壳内仍是同源 iframe，无需改 Tab/IPC；`setWindowOpenHandler` 仍会把 code-server 内的外链交给系统浏览器，符合预期。
- `host-deck-ui/vite.config.ts` 需增加 `/ide` 代理（`ws: true`），否则 `pnpm dev` 下 iframe 404。
- 上传离线包在 Electron 中走普通浏览器上传，不依赖本机文件路径。
