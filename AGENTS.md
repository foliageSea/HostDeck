# Agent Instructions (ssh_tool)

本文件面向在本仓库中自动行动的编码代理（agentic coding agents）。目标：用最少的试错成本完成构建、测试、排查与改动，并遵循现有代码风格。

仓库概览：

- Flutter/Dart：桌面端宿主应用 + 内置 HTTP/WebSocket 服务（`lib/`，入口 `lib/main.dart`）
- Dart CLI：纯 B/S 模式服务入口（`bin/server.dart`）
- Vue 3 + TypeScript + Vite：当前主前端位于 `ssh-tool-ui-next/`
- `ssh-tool-ui/` 为历史遗留目录，不应作为默认前端开发入口

## 规则文件（Cursor/Copilot）

- 未发现 Cursor 规则：`.cursorrules`、`.cursor/rules/`
- 未发现 Copilot 规则：`.github/copilot-instructions.md`

如果后续新增上述文件，请把它们的约束视为最高优先级，并同步更新本 `AGENTS.md`。

## 常用命令（Build/Lint/Test）

### Flutter/Dart（仓库根目录）

依赖：

- `flutter pub get`

静态分析：

- `flutter analyze`

格式化：

- `dart format .`

运行测试：

- `flutter test`

运行单个测试文件：

- `flutter test test/monitor_service_test.dart`
- `flutter test test/docker_engine_mapper_test.dart`

只跑名称匹配的测试：

- `flutter test --name "MonitorService parses system status correctly"`

构建（依平台）：

- Windows：`flutter build windows --release`
- macOS：`flutter build macos --release`
- Linux：`flutter build linux --release`
- Android：`flutter build apk --release`

Flutter 桌面调试：

- Flutter 端：`flutter run -d windows`
- 但调试时还需要同时启动前端 Vite，见下方“前端”部分

纯 Dart B/S 模式：

- 先构建前端：`pnpm --dir ssh-tool-ui-next build`
- 再启动服务：`dart run bin/server.dart --host 0.0.0.0 --port 8080 --web-dir ssh-tool-ui-next/dist`

CLI 构建：

- `dart build cli --target bin/server.dart -o build/server`

说明：

- `bin/server.dart` 未显式传 `--web-dir` 时，会尝试自动发现可执行文件旁的 `../web`
- GitHub Actions 的发布工作流（`.github/workflows/release.yml`）当前使用 `ssh-tool-ui-next/dist` 作为前端产物来源
- 仓库中的 `scripts/build_server.sh` 与 `scripts/build_server.ps1` 仍引用旧目录 `ssh-tool-ui/`，执行前先确认并修正路径

### 前端（`ssh-tool-ui-next/`）

依赖安装：

- `pnpm install`

开发运行：

- `pnpm dev`

构建：

- `pnpm build`

预览构建产物：

- `pnpm preview`

类型检查：

- `pnpm exec vue-tsc -p tsconfig.app.json --noEmit`

Lint/Format：

- 未发现 ESLint/Prettier 配置与脚本
- 当前主要依赖 TypeScript 编译约束、构建校验和人工保持风格一致

测试：

- 未发现 Vitest/Jest 配置或前端测试目录（无 `*.test.*` / `*.spec.*` / `vitest.config.*`）

### 端口与联调

- 后端默认监听 `http://localhost:8080`
- `ssh-tool-ui-next` 的 Vite 开发服务器默认是 `http://localhost:5173`
- `ssh-tool-ui-next/vite.config.ts` 会把 `/api` 和 `/socket.io` 代理到 `http://localhost:8080`
- Flutter 桌面应用在 `kDebugMode` 下会直接加载 `http://localhost:5173`，所以本地调试桌面壳时必须同时启动 Vite
- Flutter release 构建依赖 `assets/web/`；CLI bundle 则通常依赖 `build/server/bundle/web/`

## 代码风格与约定

### 通用

- 优先做“最小正确改动”，避免无需求的大面积重构
- 后端保持现有分层：`controllers/` 负责 HTTP 路由处理，`services/` 负责业务逻辑，`repositories/` 负责 SSH/DB 抽象，`models/` 负责数据结构
- 若改动涉及打包或发布流程，优先同时核对 `Dockerfile`、`.github/workflows/release.yml` 和相关脚本的前端目录是否一致

### Dart/Flutter 代码风格

导入顺序：

- 保持 `dart:` 标准库 -> `package:` 三方/本包 -> 相对导入 的顺序
- 不要混用相对导入与 `package:ssh_tool/...` 去引用同一层级模块

格式化：

- 使用 `dart format`

类型与空安全：

- 避免 `dynamic`，优先显式类型与泛型（例如 `Result<T>`）
- 对可空值优先使用 guard clauses，减少深层嵌套

命名：

- 类：`UpperCamelCase`
- 方法/变量：`lowerCamelCase`
- 私有字段：以下划线前缀
- 文件名：`snake_case.dart`

错误处理与 API 返回：

- 后端有统一响应模型 `Result<T>`（`lib/server/models/result.dart`）
- 成功：`Result.ok(data)`，`code = 200`
- 失败：`Result.fail(code, message)`，多数业务错误仍通过 HTTP 200 + 业务 `code != 200` 表达
- 流式/下载等端点可以直接返回非统一 JSON（例如文件读取、批量下载）
- `catch (e)` 不要吞异常，至少返回可诊断的 `message`

日志：

- 项目使用 `package:logging/logging.dart`
- 新增关键日志时避免输出密码、私钥、token 等敏感信息

测试：

- 单元测试放在 `test/`
- 纯解析/映射/计算逻辑优先写单测
- 当前已有手写 mock 的服务层测试，沿用这种最小 mock 边界的方式即可

### Vue/TypeScript 代码风格

目录与职责：

- `src/api/`：API 请求与类型
- `src/stores/`：Pinia 状态管理
- `src/lib/`：HTTP、全局 UI、壁纸存储等基础设施
- `src/views/`：业务窗口页面，常见形式是目录 + `index.vue`
- `src/components/`：通用组件与桌面壳组件

TypeScript 约束：

- `tsconfig.app.json` 已启用 `noUnusedLocals`、`noUnusedParameters`、`noFallthroughCasesInSwitch`
- 避免引入未使用变量/参数，否则类型检查会直接失败

导入与路径别名：

- 已配置别名 `@/* -> src/*`
- 跨目录引用优先使用 `@/xxx`

命名：

- 通用组件文件通常使用 `UpperCamelCase.vue`
- 路由/视图入口常使用目录 + `index.vue`
- store 文件按领域命名，现有风格包含 `ssh.ts`、`settings.ts`、`window-session.ts`、`file-clipboard.ts`
- 类型名使用 `UpperCamelCase`

错误处理与请求：

- 统一复用 `ssh-tool-ui-next/src/lib/http.ts` 中的 Axios 实例 `http`
- 若后端返回 unified `Result` 结构，`http.ts` 会在 `code === 200` 时自动解包 `data`
- 业务错误会转换成 `AxiosError`，调用方需要显式处理，不要静默失败
- SSH 会话失效场景已经在 `http.ts` 中有集中清理与提示逻辑，避免重复发明一套会话失效处理

UI 交互：

- 全局消息、通知、确认框统一走 `ssh-tool-ui-next/src/lib/ui.ts`
- 避免在深层工具函数里直接操作 UI；如果必须，保持与现有 `ui.ts` 用法一致

响应与数据结构：

- 优先复用 `ssh-tool-ui-next/src/api/*.ts` 中已有类型
- 不要在组件内随意重复声明后端响应接口

样式：

- 当前 UI 基于 Naive UI + UnoCSS
- 优先复用现有 UnoCSS utility 和 `uno.config.ts` 里的 shortcuts
- 需要自定义样式时，优先放在组件内；全局样式集中在 `ssh-tool-ui-next/src/style.css`

## 改动前检查清单（代理执行）

1. Flutter/Dart 改动：`dart format .` + `flutter analyze` + 相关 `flutter test ...`
2. 前端改动：在 `ssh-tool-ui-next/` 下执行 `pnpm build`，必要时再执行 `pnpm exec vue-tsc -p tsconfig.app.json --noEmit`
3. 若修改 API 合约：同步更新 `ssh-tool-ui-next/src/api/` 类型与调用点，确认 `src/lib/http.ts` 的解包/错误处理仍匹配
4. 若修改打包链路：确认 `Dockerfile`、`.github/workflows/release.yml`、`assets/web/` 准备流程与实际前端目录保持一致
