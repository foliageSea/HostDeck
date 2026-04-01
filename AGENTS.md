# Agent Instructions (ssh_tool)

本文件面向在本仓库中自动行动的编码代理（agentic coding agents）。目标：用最少的试错成本完成构建、测试、排查与改动，并遵循现有代码风格。

仓库概览：
- Flutter/Dart：桌面端宿主应用 + 内置 HTTP/WebSocket 服务（`lib/`）
- Vue 3 + TypeScript + Vite：前端 UI（`ssh-tool-ui/`）

## 规则文件（Cursor/Copilot）

- 未发现 Cursor 规则：`.cursorrules`、`.cursor/rules/`
- 未发现 Copilot 规则：`.github/copilot-instructions.md`

如果后续新增上述文件，请把它们的约束视为最高优先级，并同步更新本 `AGENTS.md`。

## 常用命令（Build/Lint/Test）

### Flutter/Dart（仓库根目录）

依赖：
- `flutter pub get`

静态分析（lint）：
- `flutter analyze`

格式化：
- `dart format .`

运行测试：
- `flutter test`

运行单个测试文件：
- `flutter test test/monitor_service_test.dart`

只跑名称匹配的测试（适合“单个 test case”）：
- `flutter test --name "MonitorService parses system status correctly"`

构建（依平台）：
- Windows：`flutter build windows --release`
- macOS：`flutter build macos --release`
- Linux：`flutter build linux --release`
- Android：`flutter build apk --release`

开发运行：
- Windows：`flutter run -d windows`

说明：CI 的发布工作流（`.github/workflows/release.yml`）会先构建前端 `dist`，再把产物放到 `assets/web/` 参与 Flutter 各平台打包。

### 前端（`ssh-tool-ui/`）

依赖安装：
- 推荐 pnpm（README/CI 使用）：`pnpm install`

开发运行：
- `pnpm dev`

构建：
- `pnpm build`

预览构建产物：
- `pnpm preview`

类型检查：
- 仓库已配置 TypeScript `strict: true`（见 `tsconfig.app.json`）。
- `package.json` 当前未提供 `typecheck` 脚本，但存在 `vue-tsc` 依赖。
- 可手动运行：`pnpm exec vue-tsc -p tsconfig.app.json --noEmit`

Lint/Format：
- 未发现 ESLint/Prettier 配置与脚本（`eslint*`/`prettier*` 不存在）。
- 现阶段主要依赖：TypeScript 编译选项约束 + 代码审查 +（必要时）手动保持格式一致。

测试：
- 未发现 Vitest/Jest 配置或前端测试目录（无 `*.test.*`/`*.spec.*`/`vitest.config.*`）。

### 端口与联调

- Flutter 后端 README 提到默认 `http://localhost:8080`（可能是应用内置服务端口）。
- 前端 Vite dev proxy 指向 `http://localhost:8081`（见 `ssh-tool-ui/vite.config.ts`）。

联调前请确认后端实际监听端口与前端 proxy 目标一致（必要时统一为同一个端口）。

## 代码风格与约定

### 通用

- 优先做“最小正确改动”。避免一次性重构大面积代码，除非需求明确。
- 保持现有目录分层：`controllers/` 负责 HTTP 路由处理，`services/` 负责业务逻辑，`repositories/` 负责底层 SSH/DB 抽象，`models/` 为数据结构。

### Dart/Flutter 代码风格

导入（imports）顺序：
- 现有代码普遍按：`dart:` 标准库 -> `package:` 三方/本包 -> 相对导入（`../`）
- 保持同一文件内一致；不要混用相对导入与 `package:ssh_tool/...` 导入去引用同一层级模块。

格式化：
- 使用 `dart format`；不要手写对齐空格。

类型与空安全：
- 避免 `dynamic`。优先显式类型与泛型（例如 `Result<T>`）。
- 对可空值使用早返回（guard clauses），减少深层嵌套。

命名：
- 类：`UpperCamelCase`（如 `FileController`）
- 方法/变量：`lowerCamelCase`
- 私有字段：以下划线前缀（如 `_sshService`）
- 文件名：`snake_case.dart`

错误处理与 API 返回：
- 后端有统一响应模型 `Result<T>`（`lib/server/models/result.dart`）：
  - 成功：`Result.ok(data)`，code=200
  - 失败：`Result.fail(code, message)`，注意它仍返回 HTTP 200（业务错误用 `code != 200` 表达）
- 但也存在“流式/下载”等端点直接返回非统一 JSON（例如 `readFile`/`batchDownload` 使用 `Response.ok(stream)` 或 `Response.internalServerError(...)`）。
- 新增/修改 API 时：
  - 普通 JSON 端点尽量统一用 `Result.ok/fail`
  - 二进制流端点按需使用 HTTP status code，并与前端 Axios 拦截器逻辑兼容
  - `catch (e)` 不要吞异常；至少返回可诊断的 message（当前代码多用 `e.toString()`）

日志：
- 项目使用 `package:logging/logging.dart`（多个服务/主程序已引用）。
- 若新增关键路径日志，避免输出敏感信息（密码、私钥、token、远端路径中的机密等）。

测试（Flutter）：
- 单元测试放在 `test/`。
- 写新测试时：
  - 只 mock 最小边界（当前示例 `monitor_service_test.dart` 采用手写 mock repository）
  - 纯解析/计算逻辑优先写单测；UI 行为用 `testWidgets`

### Vue/TypeScript 代码风格

TypeScript 严格性：
- `strict: true`、`noUnusedLocals: true`、`noUnusedParameters: true`（`tsconfig.app.json`）
- 避免引入未使用变量/参数；会直接触发类型检查失败。

导入与路径别名：
- 已配置别名 `@/* -> src/*`（`tsconfig` 与 `vite.config.ts`）。
- 约定：跨目录引用优先用 `@/xxx`，同目录短引用可用相对路径。

命名：
- 组件：`.vue` 文件名 `UpperCamelCase.vue`（当前如 `SystemMonitor.vue`、`FileGrid.vue`）
- composable：`useXxx.ts`（当前 `useFileOperations.ts` 等）
- store：按领域命名（`stores/file.ts`、`stores/ssh.ts`）
- 类型：`UpperCamelCase`（`interface SavedServer` 等）

错误处理（前端）：
- `src/lib/http.ts` 定义了 Axios 实例 `http` 并统一处理响应：
  - 若后端返回 unified `Result` 结构（含 `code:number`），code=200 时会把 `response.data` 解包为 `data.data`
  - code!=200 时会构造 `AxiosError` 并 `Promise.reject`
  - 对非 2xx 的 HTTP 错误仍会尝试解析 `{code,message}`，并对会话断开做 toast + 清 session
- 新增 API 调用时：
  - 尽量复用 `http` 实例（不要直接用裸 `axios`）
  - 业务错误用 try/catch 或 query error boundary 处理，不要静默失败
  - 避免在深层工具函数里直接做 UI 交互（toast/redirect）；如果必须，保持与现有 `http.ts` 逻辑一致

响应与数据结构：
- 前端 API 层通常在 `ssh-tool-ui/src/api/*.ts` 定义 request/response 类型。
- 避免在组件内随意声明重复的接口类型；优先复用 API/Store 层导出的类型。

CSS/样式：
- 使用 Tailwind（`tailwind.config.js`）与组件库（shadcn-vue / reka-ui / radix-vue）。
- 新增样式优先 Tailwind utility；若必须写自定义 CSS，集中在合理位置（例如 `src/style.css` 或组件 scoped）。

## 改动前检查清单（代理执行）

1. Flutter 改动：`dart format .` + `flutter analyze` + 相关 `flutter test ...`
2. 前端改动：`pnpm build`（必要时加 `pnpm exec vue-tsc -p tsconfig.app.json --noEmit`）
3. 若修改 API 合约：同步更新前端 `src/api/` 类型与调用点，确认 `http.ts` 解包/错误处理仍匹配
