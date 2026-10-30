# IDE（code-server）模块

> 状态：MVP 已实现（远端 Linux 离线安装 + 同源代理 + 多目标窗口骨架）。
> 设计背景与取舍见 docs/analysis/code-server-feasibility.md 与 docs/analysis/code-server/remote-implementation-plan.md。

## 功能边界

- IDE 只运行在 **SSH 目标 Linux 主机**，不在 HostDeck 所在机启动。
- 安装使用 **离线包**：管理员上传或放入数据目录，经 SSH/SFTP 推送到目标机，不依赖目标机外网。
- 每个 SSH 连接一个 IDE 会话；同一目标重复打开时复用（按 hostKey 判断）。
- 运行窗口内嵌 iframe 加载同源 /ide/ 反向代理；code-server 只监听远端 127.0.0.1，不暴露端口；工具栏保留“新标签页”按钮。

## 代码入口

后端（lib/server/features/code_server/）：

- code_server_models.dart：IdePackage、IdePreflight、IdeLaunch、IdeSessionSnapshot、RemoteIdeProvider 接口。
- code_server_proxy.dart：/ide/ 的 HTTP 与 WebSocket 反代（剥离前缀、重写 Host/Origin、gzip 透传）。
- code_server_proxy_middleware.dart：Pipeline 前缀分流；不命中时原样放行。
- code_server_manager.dart：会话注册、安装/启动/停止、健康检查、租约、代理解析。
- remote_ide_provider.dart：SSH 预检、SFTP 上传、解压、校验、启动/停止。
- loopback_ssh_bridge.dart：127.0.0.1:0 监听 → SSH direct-tcpip，HTTP/WS 共用。
- ide_package_store.dart：离线包缓存、sha256、列表、删除、扫描 offline 目录。
- code_server_controller.dart：/api/code-server/* 接口。

路由与组装：

- lib/server/routes/code_server_routes.dart
- lib/server/app/server_container.dart（依赖注册与 dispose）
- lib/server/app/server_handlers.dart（Pipeline 中挂 codeServerProxyMiddleware）
- lib/server/routes/api_routes.dart

前端：

- host-deck-ui/src/api/code-server.ts
- host-deck-ui/src/views/CodeServer/index.vue（状态、预检、上传、安装、启动、iframe、包管理抽屉；支持新标签页打开）
- host-deck-ui/src/lib/host-desktop-apps.ts、types/desktop.ts、lib/app-icons.ts、components/common/AppIcon.vue（应用注册）
- host-deck-ui/vite.config.ts（开发态 /ide 代理，ws: true）

## API

- GET /api/code-server/packages：离线包数组。
- POST /api/code-server/packages?version=<v>&arch=<amd64|arm64>：原始 tar.gz body，流式落盘，≤600MB。
- DELETE /api/code-server/packages/<id>
- POST /api/code-server/packages/scan：扫描 <dataDir>/code-server/offline 导入。
- GET /api/code-server/targets/<connectionId>/status：connection、preflight、preflightError、packages、session。
- POST /api/code-server/targets/<connectionId>/install {packageId}
- POST /api/code-server/targets/<connectionId>/start {folder?}
- POST /api/code-server/targets/<connectionId>/stop
- POST /api/code-server/targets/<connectionId>/uninstall：停止同一目标的 IDE 会话并卸载 HostDeck 管理的所有 code-server 版本，保留项目、用户设置、扩展和 HostDeck 离线包。
- GET /ide/<sessionId>/...：反向代理（自行鉴权，不受 /api 中间件保护）。

普通接口使用 Result.ok/fail。注意：Cascade 会在 404 时继续往下走，因此控制器不要依赖 404 传递业务错误（connection 缺失时 status 返回 200 + preflightError）。

## 数据与端口

HostDeck 端：

- <dataDir>/code-server/packages/<version>/linux-<arch>.tar.gz（+ sidecar JSON）
- <dataDir>/code-server/offline/（手工投放目录）
- <dataDir>/code-server/tmp/（上传临时文件）

远端：

- ~/.local/lib/hostdeck/code-server/<version>/（解压后的 code-server）
- ~/.local/share/hostdeck/code-server/<hostKey>/{data,extensions,logs,sessions}
- hostKey = sha256(SSH targetKey)[0:12]；同一目标重连后复用。

端口：

- code-server 监听远端 127.0.0.1，端口从 18090 + FNV(hostKey)%100 起，冲突时 +1 重试。
- HostDeck 本地 bridge 绑定 127.0.0.1:0（随机）。
- 禁止把 code-server 改成 0.0.0.0；禁止直接映射端口。

设置中的“后端端口”通过 `/api/settings/ports` 汇总运行中的 IDE 内部隧道，显示本地监听地址、远端目标、SSH 连接 ID、活跃连接数、启动时间和 `/ide/<sessionId>/` 访问路径。停止或 SSH 断开后，刷新列表即移除；同一目标复用的会话只显示一条，不会为查询创建隧道。

## 启动参数

code-server 固定参数：

    --auth none
    --bind-addr 127.0.0.1:<port>
    --enable-remote-storage
    --disable-telemetry
    --disable-update-check
    --disable-workspace-trust
    --user-data-dir <dataDir>
    --extensions-dir <extensionsDir>
    --idle-timeout-seconds 3600

--enable-remote-storage 把工作台状态写到远端 user-data-dir，避免多会话共享浏览器 IndexedDB；若初始化失败 code-server 会回退浏览器存储。

## 生命周期与 SSH 约束

- 安装/启动期间持有 code-server:op:<sessionId> 租约，运行期间持有 code-server:<sessionId> 租约；代理请求会 touch 连接，避免 120s 空闲回收拆掉隧道。
- 健康检查由 HostDeck 经本地 bridge 请求 /healthz，不依赖远端 curl。
- 停止：SIGTERM → 轮询 → SIGKILL，删除远端 sessions/<sessionId>.json；SSH 断开时关闭 bridge，远端进程靠 --idle-timeout-seconds 兜底。
- 卸载：在 IDE 工具栏点击“卸载 IDE”并确认；先停止同目标的已知会话，再移除远端所有 HostDeck 管理的程序版本。保留项目、设置和扩展，离线包可用于重新安装。安装、启动与卸载按目标互斥，停止失败时中止卸载。
- HostDeck 退出时 best-effort 停止所有会话。

## IDE 端口预览

通过 `/ide/<sessionId>/proxy/<port>/` 访问远端应用时，代理会为 HTML、JavaScript 和 CSS 中的根路径资源补上转发前缀，并适配 Vite 客户端的 HMR WebSocket 地址；根路径重定向也留在同一预览目录。gzip 文本解压后重写，图片等二进制资源保持透传。只有端口预览响应启用此逻辑，IDE 工作台本身不做正文重写。

这是常见开发服务器的兼容处理：动态拼接的根路径、写死的绝对域名、自定义 WebSocket 地址、Service Worker 作用域及基于站点根目录的路由，仍可能需要被预览应用配置自己的 base/public path。应用已经配置完整转发前缀时不会重复添加。

HTTP／WebSocket 代理和正文适配的公共实现位于 `core/http/path_http_proxy.dart`、`proxy_content_rewriter.dart`；独立 HTTP 端口转发复用该实现，详见 [端口转发](port-forwards.md)。

## 已知限制

1. 未实现 HostDeck 重启后的远端进程**接管**：重启后会按新端口启动新实例，旧实例依赖 1 小时 idle timeout 回收。
2. 同一目标多个 connectionId 会复用同一会话，但 stop 需要使用当前运行连接的 connectionId。
3. 代理对同机其他用户不是强隔离：远端 --auth none 只保证不暴露到网络，共享主机上同机用户理论上可访问 loopback 端口。需要强隔离时再加随机密码或 Unix socket。
4. 未实现安装/启动的 SSE 进度，前端用 1s 轮询；大包上传用 XHR 进度。
5. 未实现 VSIX 离线安装、code-server 版本切换 UI、CLI 参数（offline-dir/max-sessions 等）；版本目前取离线包版本。
6. 未实现共享主机多用户模型；按 HostDeck 单管理员设计。
7. IDE 的安装/启动/停止未写入操作日志（operation_logs）；访问日志对 /ide/ 仅打印 FINE 级别。

## 验证

- fvm flutter analyze
- fvm flutter test test/code_server_proxy_test.dart test/code_server_package_store_test.dart test/remote_ide_provider_test.dart
- pnpm --dir host-deck-ui build
- 真实链路（本地 sshd + 219MB 离线包）：上传 → 安装（约 17s）→ 启动（约 2s）→ /ide/ HTML 200、workbench.js 5.4MB 200、/healthz 正常、带 Cookie 的 WS 升级成功。

## 性能与诊断

- SSH 依赖使用 dartssh2 4.1.0+：旧版 2.22.0 在背压暂停期间耗尽 2 MiB 接收窗口后，
  恢复读取也不会补窗，可能表现为 WebSocket 握手成功但初始化持续超时、反复重连。
  回归测试 test/ide_ssh_flow_control_test.dart 覆盖暂停恢复和延迟订阅两条路径。
  升级后需重启 HostDeck 后端并重新建立 SSH 连接，已有通道不会自动获得修复。
- 启动成功后由 running 状态挂载 iframe，不再额外修改 key 重建；手动刷新仍会重新加载。

- 每次启动 code-server 前，会在远端 dataDir/User/settings.json 中补充缺失的
  files.watcherExclude（node_modules、.dart_tool、build、dist、release、.fvm、.gradle 等），
  并只在缺失时写入 search.followSymlinks=false；已有配置不覆盖，JSONC/非法 JSON 会跳过。
- 代理对每条 WebSocket 记录 open/close 日志：
  session、path、firstClose（browser/upstream）、durationMs、双向字节数和错误，
  用于区分是页面关闭/刷新、上游结束还是代理异常。
