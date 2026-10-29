# IDE（code-server）模块

> 状态：MVP 已实现（远端 Linux 离线安装 + 同源代理 + 多目标窗口骨架）。
> 设计背景与取舍见 docs/analysis/code-server-feasibility.md 与 docs/analysis/code-server/remote-implementation-plan.md。

## 功能边界

- IDE 只运行在 **SSH 目标 Linux 主机**，不在 HostDeck 所在机启动。
- 安装使用 **离线包**：管理员上传或放入数据目录，经 SSH/SFTP 推送到目标机，不依赖目标机外网。
- 每个 SSH 连接一个 IDE 会话；同一目标重复打开时复用（按 hostKey 判断）。
- 启动后在新标签页打开 **同源 /ide/ 反向代理**；code-server 只监听远端 127.0.0.1，不暴露端口，也不再使用内嵌 iframe。

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
- host-deck-ui/src/views/CodeServer/index.vue（状态、预检、上传、安装、启动、包管理抽屉；启动后打开新标签页）
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
- HostDeck 退出时 best-effort 停止所有会话。

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
