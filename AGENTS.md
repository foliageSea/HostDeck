# Agent Instructions (ssh_tool)

## Scope

- 根目录是 Flutter/Dart 桌面壳和内置 HTTP/WebSocket 服务；入口 `lib/main.dart`。
- `bin/server.dart` 是纯 Dart B/S 服务入口，可不启动 Flutter UI。
- 当前前端只使用 `ssh-tool-ui-next/`；旧 `ssh-tool-ui/` 目录当前不存在，但 `scripts/build_server.ps1`、`scripts/build_server.sh` 仍引用旧路径，执行前必须修正为 `ssh-tool-ui-next/`。
- `CLAUDE.md` 仍指向旧前端路径，不能作为当前前端来源；README、`package.json`、`vite.config.ts`、CI、Dockerfile 更可信。

## Commands

- 后端/桌面依赖：`flutter pub get`
- Dart/Flutter 分析：`flutter analyze`
- Dart/Flutter 测试：`flutter test`
- 单个测试文件：`flutter test test/monitor_service_test.dart`
- 按名称跑测试：`flutter test --name "MonitorService parses system status correctly"`
- Dart 格式化：`dart format .`
- 前端依赖：`pnpm --dir ssh-tool-ui-next install`
- 前端开发：`pnpm --dir ssh-tool-ui-next dev`
- 前端构建：`pnpm --dir ssh-tool-ui-next build`
- 前端类型检查：`pnpm --dir ssh-tool-ui-next exec vue-tsc -p tsconfig.app.json --noEmit`
- 前端测试：`pnpm --dir ssh-tool-ui-next test`
- 单个前端测试：`pnpm --dir ssh-tool-ui-next exec vitest run src/views/Files/components/__tests__/FilePickerDialog.spec.ts`
- 纯 B/S 本地运行：先 `pnpm --dir ssh-tool-ui-next build`，再 `dart run bin/server.dart --host 0.0.0.0 --port 8080 --web-dir ssh-tool-ui-next/dist`
- Docker 本地构建：`docker build -t ssh-tool:local .`

## Dev Servers And Packaging

- 后端默认监听 `http://localhost:8080`。
- Vite 配置实际端口是 `5174`；`README.md` 中的 `5173` 是旧信息。
- Vite 代理 `/api` 和 `/socket.io` 到 `VITE_DEV_PROXY_TARGET`，默认 `http://localhost:8080`。
- Flutter debug 的 WebView 仍硬编码加载 `http://localhost:5173`（`lib/main.dart`），如要调试桌面壳需先统一该端口或让 Vite 使用 5173。
- Flutter release 使用 `assets/web/` 作为静态资源；本地桌面 release 前要先构建前端并同步 `ssh-tool-ui-next/dist` 到 `assets/web/`。
- CI release 会构建 `ssh-tool-ui-next/dist`，Windows 桌面 job 下载到 `assets/web`，Dockerfile 直接复制 `ssh-tool-ui-next/dist` 到 `/app/web`。
- `bin/server.dart` 未传 `--web-dir` 时只会查找可执行文件旁 `../web`；开发运行通常要显式传 `--web-dir ssh-tool-ui-next/dist`。

## Backend Notes

- 服务组装在 `lib/server/server_service.dart`：controllers 处理路由，services 处理业务，repositories 处理 SSH/DB 抽象，models 定义数据。
- 普通 JSON API 使用 `lib/server/models/result.dart`：`Result.ok(...)` 和 `Result.fail(...)` 都返回 HTTP 200，业务错误靠 JSON `code != 200`。
- 流式、下载、静态资源和部分 WebSocket 路由不一定走统一 `Result` JSON。
- 新日志使用 `package:logging/logging.dart`，不要记录密码、私钥、token。

## Frontend Notes

- 前端源码入口 `ssh-tool-ui-next/src/main.ts`；API 类型/请求在 `src/api/`，Pinia 在 `src/stores/`，HTTP/UI 基础设施在 `src/lib/`，业务窗口在 `src/views/`。
- `tsconfig.app.json` 开启 `noUnusedLocals`、`noUnusedParameters`、`erasableSyntaxOnly`、`noFallthroughCasesInSwitch`；未使用导入/参数会让类型检查失败。
- 路径别名是 `@/* -> src/*`；跨前端目录引用优先用 `@/xxx`。
- 普通 API 请求复用 `src/lib/http.ts` 的 Axios 实例；它会把 `code === 200` 的统一响应解包成 `data`，并把业务错误转成 `AxiosError`。
- 全局消息、通知、确认框走 `src/lib/ui.ts`；避免在工具函数里另起 UI 通道。
- UI 基于 Naive UI + UnoCSS；自动导入会生成 `auto-imports.d.ts`、`components.d.ts`。

## Verification Rules

- Dart/Flutter 改动至少跑 `dart format .`、`flutter analyze` 和相关 `flutter test ...`。
- 前端改动至少跑 `pnpm --dir ssh-tool-ui-next build`；涉及类型边界或测试逻辑时再跑 `vue-tsc` 和相关 `vitest run ...`。
- API 合约改动要同步 `lib/server/controllers/*`、`ssh-tool-ui-next/src/api/*` 和调用点，并确认 `src/lib/http.ts` 的统一解包仍匹配。
- 打包链路改动要同时核对 `Dockerfile`、`.github/workflows/release.yml`、`pubspec.yaml` 的 `assets/web/` 声明和服务打包脚本。
