# 终端模块

终端模块负责基于当前 SSH 连接创建交互式 shell，并在前端使用 xterm.js 展示。

## 代码入口

后端：

- `lib/server/controllers/terminal_controller.dart`
- `lib/server/services/ssh_service.dart`
- `lib/server/models/ssh_operation_limiter.dart`

前端：

- `ssh-tool-ui-next/src/api/terminal.ts`
- `ssh-tool-ui-next/src/views/Terminal/index.vue`
- `ssh-tool-ui-next/src/views/Terminal/hooks/useTerminalSession.ts`
- `ssh-tool-ui-next/src/views/Terminal/components/TerminalSettingsModal.vue`
- `ssh-tool-ui-next/src/stores/desktop.ts`

## API 与通道

- `GET /api/ws/terminal`：终端 WebSocket 通道。
- `POST /api/terminal/session`：创建终端会话。
- `DELETE /api/terminal/session`：关闭终端会话。

## 开发要点

- 终端是会话型能力，应明确创建、绑定、关闭和异常断开流程。
- 前端窗口系统中 `terminal` 属于 session window，受 `maxSessionWindows = 8` 限制。
- xterm 初始化、fit addon、web links addon 等逻辑应保持在终端 view 或 hook 内，不要扩散到全局 store。
- 后端应在客户端断开时释放 SSH channel，避免远端 shell 泄漏。
- 终端设置属于前端体验配置，和后端 SSH 会话生命周期分离。

## 常见修改点

- 新增终端快捷键：优先修改 `Terminal/index.vue` 或相关 hook。
- 调整终端会话创建参数：同步 `terminal_controller.dart` 和 `src/api/terminal.ts`。
- 调整窗口数量限制：修改 `src/stores/desktop.ts` 中的 `maxSessionWindows`，并评估资源占用。
