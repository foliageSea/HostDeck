# 后端开发说明

后端位于 `lib/server/`，使用 Dart、shelf、shelf_router、shelf_web_socket、dartssh2、sqlite3 和 logging。

## 目录职责

- `lib/server/app/server_service.dart`：服务依赖组装、HTTP 绑定、静态资源和 SPA fallback。
- `lib/server/routes/api_routes.dart`：集中注册 HTTP 与 WebSocket 路由。
- `lib/server/features/<feature>/`：按功能收拢 controller、service、repository 与领域模型。
- `lib/server/core/`：SSH、HTTP、数据库等跨功能基础设施。
- `lib/server/app/`：运行时依赖组装与服务生命周期。

## 入口

桌面内置服务由 `lib/main.dart` 启动，纯 B/S 服务由 `bin/server.dart` 启动。两者最终都使用 `ServerService`。

`bin/server.dart` 支持参数：

- `--host <value>`：绑定地址，默认 `0.0.0.0`。
- `--port <value>`：绑定端口，默认 `8080`。
- `--web-dir <path>`：静态前端资源目录。
- `--data-dir <path>`：sqlite 与配置目录。
- `--help`：打印帮助。

## 路由注册

所有业务路由集中在 `lib/server/routes/api_routes.dart`。新增后端接口时，通常需要同步：

- 新增或修改 `lib/server/features/<feature>/*`。
- 如需跨功能 SSH、HTTP 或数据库能力，新增或修改 `lib/server/core/*`。
- 在 `lib/server/app/server_container.dart` 中组装依赖。
- 在 `ApiRoutes.router` 中注册路由。
- 在 `host-deck-ui/src/api/*` 添加前端请求封装。
- 更新调用该 API 的 store、hook 或 view。

## 响应约定

普通 JSON API 使用 `lib/server/core/http/result.dart`：

- 成功：`Result.ok(data)`。
- 失败：`Result.fail(message, code: ...)`。
- 业务错误通常仍返回 HTTP 200，前端靠 JSON `code != 200` 判断失败。

流式响应、下载响应、静态资源和部分 WebSocket 路由不一定使用统一 JSON 响应。

## 静态资源

`ServerService` 在 `webDir` 非空时创建静态资源处理器：

- 默认文档是 `index.html`。
- API 未命中时返回 `API Route not found`。
- 非 API 路由未命中时尝试返回 `index.html`，用于 Vue SPA fallback。

## 数据目录

`DatabaseService` 由 `ServerService` 初始化，`bin/server.dart` 会通过 `AppSettings.configure(dataDir: config.dataDir)` 配置运行数据目录。需要持久化的数据应通过 feature repository 或 `core/database` 集中处理，不要在 controller 中直接操作文件或数据库。

## 日志与安全

- 使用 `package:logging/logging.dart`。
- logger 名称应能定位模块，例如 `ServerService`。
- 不要记录密码、私钥、token、SSH 登录凭据或完整敏感配置。
- 错误日志可记录异常类型和必要上下文，但应避免泄露远端命令输出中的敏感内容。
