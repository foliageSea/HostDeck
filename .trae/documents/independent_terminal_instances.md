# 计划：独立终端实例与生命周期管理

## 摘要

重构 SSH 会话管理，支持在单个 SSH 连接上复用多个独立的终端实例（Shell）。更新前端 `Terminal` 组件，使其在每个窗口打开时请求一个新的 Shell 会话，并在窗口关闭时销毁该会话。

## 当前状态分析

* **后端**：`SshService` 在连接时创建一个包含 Client 和 Shell 的单一 `SshSession`。关闭会话会同时关闭 SSH Client。

* **前端**：`sshStore` 保存单一的 `sessionId`。所有 `Terminal` 组件共享此会话。关闭窗口仅卸载组件，但保持会话（和 Shell）存活。

* **问题**：所有终端窗口实际上是同一个 Shell 的镜像。关闭窗口不会清理 Shell。

## 建议变更

### 1. 后端：重构 SSH 服务 (`lib/server/services/ssh_service.dart` & `models/ssh_session.dart`)

* **解耦 Client 和 Session**：

  * 维护 `_clients` 映射 (`connectionId` -> `SSHClient`)。

  * 维护 `_sessions` 映射 (`sessionId` -> `SshSession`)。

* **更新** **`SshSession`**：

  * 添加 `connectionId` 字段。

  * 修改 `close()` 方法，使其**仅**关闭 `shell` 和 `outputController`，**不**关闭 `client`。

* **更新** **`SshService`**：

  * `connect(...)`：

    * 创建 `SSHClient`。

    * 生成 `connectionId`。

    * 存储 `client`。

    * 创建初始 `SshSession`（主会话）。

    * 处理 `client.done` 以关闭所有相关会话。

    * 返回 `SshSession`（包含 `connectionId`）。

  * `createShell(connectionId)`：

    * 查找 Client。

    * 打开新 Shell (`client.shell()`)。

    * 创建并存储新 `SshSession`。

    * 返回新 `SshSession`。

  * `disconnect(connectionId)`：

    * 关闭 `SSHClient`。

    * 关闭此连接的所有会话。

* **API 更新**：

  * 更新 `AuthController.connect`，在响应中返回 `connectionId`。

  * 添加 `TerminalController.createSession(connectionId)` 端点。

  * 添加 `TerminalController.closeSession(sessionId)` 端点。

### 2. 前端：更新 Store 和终端逻辑 (`ssh-tool-ui/src/`)

* **Store (`stores/ssh.ts`)**：

  * 添加 `connectionId` 状态。

  * 更新 `setSession` 以接受 `connectionId`。

* **登录 (`views/Home.vue`** **或等效逻辑)**：

  * 更新登录逻辑以保存响应中的 `connectionId`。

* **终端组件 (`views/Terminal.vue`)**：

  * **挂载 (Mount)**：

    * 调用 API `/api/terminal/session` (POST) 使用 `sshStore.connectionId` 创建专用会话。

    * 使用返回的 `sessionId` 连接 WebSocket。

  * **卸载 (Unmount)**：

    * 调用 API `/api/terminal/session` (DELETE) 销毁会话。

### 3. API 路由 (`lib/server/routes/api_routes.dart`)

* 注册新的 `createSession` 和 `closeSession` 端点。

## 验证计划

1. **手动测试**：

   * 登录 SSH 服务器。

   * 打开终端窗口 1 -> 运行 `top`。

   * 打开终端窗口 2 -> 运行 `ls`。验证它是独立的 Shell（不显示 `top`）。

   * 关闭窗口 2。

   * 验证窗口 1 仍然活动。

   * 检查后端日志（如果可能）以确认 Shell 关闭。

   * 关闭窗口 1。

   * 注销（断开连接）-> 验证连接已关闭。

