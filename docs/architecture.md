# 整体架构

`ssh_tool` 是一个跨平台 SSH 工具，当前同时支持桌面应用形态和纯 B/S 服务形态。

## 组成部分

- Flutter 桌面壳：入口 `lib/main.dart`，负责桌面窗口、WebView 承载和内置后端服务生命周期。
- Dart HTTP/WebSocket 服务：核心组装在 `lib/server/server_service.dart`，独立入口是 `bin/server.dart`。
- Vue 3 前端：当前唯一前端工程位于 `ssh-tool-ui-next/`，构建产物由桌面壳或 Dart 服务作为静态资源提供。

## 运行形态

桌面调试模式：

- 前端通过 Vite 开发服务器运行。
- 后端由 Flutter 桌面壳内置启动，默认监听 `http://localhost:8080`。
- Vite 代理 `/api` 到后端，其中终端 WebSocket 使用 `/api/ws/terminal`。
- 注意：Vite 开发服务器端口以 `ssh-tool-ui-next/vite.config.ts` 的 `server.port` 为准；Electron 开发模式会读取该配置，也可通过 `SSH_TOOL_ELECTRON_DEV_URL` 覆盖；`lib/main.dart` debug WebView 当前仍硬编码加载 `http://localhost:5173`。

纯 B/S 模式：

- 先构建 `ssh-tool-ui-next/dist`。
- 使用 `dart run bin/server.dart --host 0.0.0.0 --port 8080 --web-dir ssh-tool-ui-next/dist` 启动。
- 服务同时提供 API、WebSocket 和前端静态资源。

发布模式：

- Flutter release 使用 `assets/web/` 作为静态资源来源。
- Docker 镜像直接复制 `ssh-tool-ui-next/dist` 到 `/app/web`。
- CLI bundle 默认尝试从可执行文件旁的 `../web` 查找静态资源。

## 服务启动流程

`ServerService.start()` 的主要步骤：

1. 检查 `webDir` 指向的静态资源目录。
2. 初始化 `DatabaseService`。
3. 创建 repository：`SshRepository`、`ServerRepository`。
4. 创建 service：`SshService`、`MonitorHistoryService`、`MonitorService`、`FileService`、`DockerService`。
5. 创建 controller：认证、系统、文件、终端、服务器配置、Docker、运行态会话。
6. 使用 `ApiRoutes` 注册 HTTP 和 WebSocket 路由。
7. 配置静态资源处理器和 SPA fallback。
8. 通过 `shelf_io.serve` 绑定地址和端口。

## 请求流转

普通 API 请求：

1. 前端通过 `ssh-tool-ui-next/src/lib/http.ts` 的 Axios 实例发起请求。
2. 请求命中 `lib/server/routes/api_routes.dart` 中注册的路由。
3. controller 负责参数解析、响应包装和错误处理。
4. service 负责业务逻辑。
5. repository 负责 SSH、Docker Engine、sqlite 等底层交互。
6. controller 返回 `Result.ok(...)` 或 `Result.fail(...)`。
7. 前端 HTTP 拦截器将 `code === 200` 的统一响应解包为 `data`。

WebSocket 请求：

- 终端使用 `/api/ws/terminal`。
- 系统监控使用 `/api/ws/monitor`。
- SSH 会话状态使用 `/api/ws/session`。
- 运行态会话使用 `/api/ws/runtime`。

## 分层原则

- `controllers` 只处理协议层细节，包括参数、路由、响应和 WebSocket 生命周期。
- `services` 处理可测试的业务逻辑。
- `repositories` 封装外部系统访问，例如 SSH、Docker Engine、sqlite。
- `models` 定义跨层传递的数据结构。
- 新日志使用 `package:logging/logging.dart`，不得记录密码、私钥、token。
