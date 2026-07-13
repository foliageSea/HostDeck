# 本地开发流程

本文档记录本项目本地开发的推荐流程。

## 前置要求

- Flutter SDK
- Node.js 20+
- pnpm

安装依赖：

```bash
flutter pub get
pnpm --dir host-deck-ui install
```

## Flutter 桌面壳调试

当前 Flutter debug 模式会在 WebView 中加载 Vite 开发服务器，同时 Flutter 侧会启动内置后端服务。

启动前端：

```bash
pnpm --dir host-deck-ui dev
```

启动桌面壳：

```bash
flutter run -d windows
```

注意：

- 后端默认监听 `http://localhost:8080`。
- Vite 开发服务器端口以 `host-deck-ui/vite.config.ts` 的 `server.port` 为准。
- Electron 开发模式由 `host-deck-electron/` 启动，并分别从 `host-deck-ui/vite.config.ts` 与 `host-deck-electron/vite.config.mjs` 读取开发服务器地址，也可通过 `HOST_DECK_ELECTRON_APP_DEV_URL` 与 `HOST_DECK_ELECTRON_SHELL_DEV_URL` 覆盖。
- `lib/main.dart` 的 Flutter debug WebView 当前仍硬编码加载 `http://localhost:5173`。
- 调试桌面壳前需要统一端口，或临时让 Vite 使用 `5173`。

## 纯 Dart B/S 模式

先构建前端，再启动服务：

```bash
pnpm --dir host-deck-ui build
$env:HOSTDECK_ACCESS_PASSWORD = 'replace-with-a-strong-password'
dart run bin/server.dart --host 0.0.0.0 --port 8080 --web-dir host-deck-ui/dist
```

启动后访问 `http://localhost:8080`。

非 loopback 监听必须通过 `HOSTDECK_ACCESS_PASSWORD` 或 `HOSTDECK_API_TOKEN` 启用访问认证。仅本机开发可省略 `--host`，默认绑定 `127.0.0.1`。完整说明见 `docs/access-control.md`。

常用参数：

- `--host <value>`：绑定地址，默认 `0.0.0.0`。
- `--port <value>`：监听端口，默认 `8080`。
- `--web-dir <path>`：静态前端资源目录。
- `--data-dir <path>`：sqlite 与配置文件目录。

## 前端独立开发

启动 Vite：

```bash
pnpm --dir host-deck-ui dev
```

Vite 会将 `/api` 代理到 `VITE_DEV_PROXY_TARGET`，默认是 `http://localhost:8080`；终端 WebSocket 使用 `/api/ws/terminal`。前端独立开发时，需要确保后端服务已经启动。

## 新功能开发流程

涉及后端 API 的功能通常按以下顺序开发：

1. 在 `lib/server/models/` 定义或调整模型。
2. 在 `lib/server/repositories/` 封装外部访问或持久化。
3. 在 `lib/server/services/` 实现业务逻辑。
4. 在 `lib/server/controllers/` 实现路由处理。
5. 在 `lib/server/routes/api_routes.dart` 注册路由。
6. 在 `host-deck-ui/src/api/` 添加前端请求和类型。
7. 在 `src/stores/`、`src/views/` 或 `src/components/` 中接入 UI。
8. 补充或更新测试。
9. 更新 `docs/` 中对应模块文档。

只涉及前端 UI 的功能通常按以下顺序开发：

1. 确认是否是桌面应用窗口、普通组件还是业务视图。
2. 如需新窗口，先更新 `src/types/desktop.ts` 和 `src/stores/desktop.ts`。
3. 实现 view、component 或 hook。
4. 使用 `src/lib/http.ts`、`src/lib/ui.ts`、Pinia store 等现有基础设施。
5. 运行前端构建、类型检查或相关测试。

## 代码风格

- 后端日志使用 `package:logging/logging.dart`。
- 前端跨目录引用优先使用 `@/xxx`。
- 前端不要保留未使用导入、变量和参数。
- 不要记录或持久化密码、私钥、token。
- 优先做小而明确的改动，避免无必要重构。
