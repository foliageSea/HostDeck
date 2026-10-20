# Agent Instructions (host_deck)

## Scope

- 根目录是 Dart 后端（HTTP/WebSocket 服务）和 Flutter 桌面壳；Flutter 入口 `lib/main.dart`。Flutter 桌面 release 已弃用，仅保留 debug 调试用途。
- `bin/server.dart` 是纯 Dart B/S 服务入口，可不启动 Flutter UI；`bin/hostdeck_cli.dart`、`bin/hostdeck_mcp.dart` 是 Agent CLI / MCP 入口。
- 当前前端只使用 `host-deck-ui/`（含子包 `host-deck-ui/packages/webos`）；桌面发行形态是 `host-deck-electron/`（Windows、macOS arm64）。
- `host-deck-ai/` 是 pi-ai bridge，由 Bun 编译为独立可执行程序。
- 仓库使用 submodule（`host-deck-ui/src/assets/mac-tahoe`），首次克隆后需要 `git submodule update --init --recursive`。
- 模块化开发文档在 `docs/`，入口 `docs/README.md`。

## Commands

- 全部依赖：`git submodule update --init --recursive`、`fvm flutter pub get`、`pnpm run install:all`
- 后端/桌面依赖：`fvm flutter pub get`
- Dart/Flutter 分析：`fvm flutter analyze`
- Dart/Flutter 测试：`fvm flutter test`
- 单个测试文件：`fvm flutter test test/monitor_service_test.dart`
- 按名称跑测试：`fvm flutter test --name "MonitorService parses system status correctly"`
- Dart 格式化：`dart format .`
- 前端依赖：`pnpm --dir host-deck-ui install`
- 前端开发：`pnpm --dir host-deck-ui dev`
- 前端构建：`pnpm --dir host-deck-ui build`
- 前端类型检查：`pnpm --dir host-deck-ui exec vue-tsc -p tsconfig.app.json --noEmit`
- 前端测试：`pnpm --dir host-deck-ui test`
- 单个前端测试：`pnpm --dir host-deck-ui exec vitest run src/views/Files/components/__tests__/FilePickerDialog.spec.ts`
- Electron 依赖：`pnpm --dir host-deck-electron install`
- Electron 开发：`pnpm --dir host-deck-electron electron:dev`
- Electron 打包：`pnpm run build:electron:win` 或 `pnpm run build:electron:mac`（macOS 仅 arm64）
- pi-ai bridge 测试：`pnpm --dir host-deck-ai test`
- 根目录聚合命令：`pnpm run check`（ui 类型检查 + ai 测试 + dart analyze）、`pnpm run test`
- 一键开发：`./dev.sh`（macOS/Linux）、`.\dev.ps1`（Windows），同时启动后端和 Vite
- 纯 B/S 本地运行：先 `pnpm --dir host-deck-ui build`，再 `dart run bin/server.dart --host 0.0.0.0 --port 8080 --web-dir host-deck-ui/dist`
- Docker 本地构建：`docker build -t host-deck:local .`

## Dev Servers And Packaging

- 后端默认监听 `http://localhost:8080`。
- Vite 开发服务器端口以 `host-deck-ui/vite.config.ts` 的 `server.port` 为准；`host-deck-electron/` 的 Electron 开发模式会分别读取前端与壳层 Vite 配置，也可通过 `HOST_DECK_ELECTRON_APP_DEV_URL` 和 `HOST_DECK_ELECTRON_SHELL_DEV_URL` 覆盖。
- Vite 代理 `/api` 到 `VITE_DEV_PROXY_TARGET`，默认 `http://localhost:8080`；终端 WebSocket 使用 `/api/ws/terminal`。
- Flutter debug 的 WebView 加载 `http://localhost:5178`（`lib/main.dart`），与 `host-deck-ui/vite.config.ts` 默认端口一致；修改其中一处需同步另一处。
- Flutter 桌面 release 已弃用：`pubspec.yaml` 的 `assets/web/` 声明已注释，`release.yml` 中对应 job 也已注释，不要再按该链路发布。
- CI release 先构建 `host-deck-ui/dist` 并作为 artifact 分发；实际发布产物为 Docker 镜像、Windows CLI zip、Electron Windows exe/zip、Electron macOS arm64 dmg/zip。Dockerfile 直接复制 `host-deck-ui/dist` 到 `/app/web`。
- `bin/server.dart` 未传 `--web-dir` 时只会查找可执行文件旁 `../web`；开发运行通常要显式传 `--web-dir host-deck-ui/dist`。

## Backend Notes

- 服务组装在 `lib/server/app/server_service.dart`（依赖容器 `server_container.dart`）：`routes/` 注册路由，`features/<feature>/` 按功能放 controller、service、repository 和模型，`core/` 放 database、http、ssh 等公共设施。
- 普通 JSON API 使用 `lib/server/core/http/result.dart`：`Result.ok(...)` 和 `Result.fail(...)` 都返回 HTTP 200，业务错误靠 JSON `code != 200`。
- 流式、下载、静态资源和部分 WebSocket 路由不一定走统一 `Result` JSON。
- 新日志使用 `package:logging/logging.dart`，不要记录密码、私钥、token。

## Frontend Notes

- 前端源码入口 `host-deck-ui/src/main.ts`；API 类型/请求在 `src/api/`，Pinia 在 `src/stores/`，HTTP/UI 基础设施在 `src/lib/`，业务窗口在 `src/views/`，通用组件在 `src/components/`，组合式函数在 `src/hooks/`。
- `pnpm dev`、`pnpm build`、`pnpm test` 会先构建 `packages/webos` 子包。
- `tsconfig.app.json` 开启 `noUnusedLocals`、`noUnusedParameters`、`erasableSyntaxOnly`、`noFallthroughCasesInSwitch`；未使用导入/参数会让类型检查失败。
- 路径别名是 `@/* -> src/*`；跨前端目录引用优先用 `@/xxx`。
- 普通 API 请求复用 `src/lib/http.ts` 的 Axios 实例；它会把 `code === 200` 的统一响应解包成 `data`，并把业务错误转成 `AxiosError`。
- 全局消息、通知、确认框走 `src/lib/ui.ts`；避免在工具函数里另起 UI 通道。
- UI 基于 Naive UI + UnoCSS；自动导入会生成 `auto-imports.d.ts`、`components.d.ts`。

## Verification Rules

- Dart/Flutter 改动至少跑 `dart format .`、`fvm flutter analyze` 和相关 `fvm flutter test ...`。
- 前端改动至少跑 `pnpm --dir host-deck-ui build`；涉及类型边界或测试逻辑时再跑 `vue-tsc` 和相关 `vitest run ...`。
- API 合约改动要同步 `lib/server/features/*/*_controller.dart`、`lib/server/routes/*`、`host-deck-ui/src/api/*` 和调用点，并确认 `src/lib/http.ts` 的统一解包仍匹配。
- 打包链路改动要同时核对 `Dockerfile`、`.github/workflows/release.yml`、`scripts/build_server.*`、`host-deck-electron/` 构建脚本。
- `host-deck-ai/` 改动跑 `pnpm --dir host-deck-ai test`；涉及可执行程序时再跑 `test:bin`。


## Commit
- 提交代码使用中文 例：`feat(file): 新增文件选择器`
