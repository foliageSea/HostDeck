# 改进 SSH 连接状态与系统状态为 WebSocket 推送方案

## 目标
当前项目使用前端 HTTP 轮询 (`@tanstack/vue-query`) 的方式每 3 秒获取系统状态，并依赖 HTTP 响应拦截器来捕获 SSH 连接断开的异常。
本计划旨在将此机制升级为 WebSocket (WS) 方案，由后端定时推送系统状态，并在 SSH 断开时主动关闭 WS 连接，前端通过监听 WS 状态来实现实时状态更新和连接状态的管理。

## 实施步骤

### 1. 更新 Vite 代理配置
- **文件**: `ssh-tool-ui/vite.config.ts`
- **操作**: 在 `server.proxy['/api']` 规则中添加 `ws: true`，以支持针对 `/api/ws/*` 路径的 WebSocket 代理转发。

### 2. 重构后端 SystemController (改为 WS 处理器)
- **文件**: `lib/server/controllers/system_controller.dart`
- **操作**:
  - 引入 `package:shelf_web_socket/shelf_web_socket.dart` 和 `package:web_socket_channel/web_socket_channel.dart`。
  - 删除原来的 `monitor` HTTP 处理方法。
  - 新增 `wsMonitor` 属性，返回一个 `webSocketHandler`。
  - 在 WS 处理器中，根据 `sessionId` 获取 SSH Session。如果无效则以 `4040` 状态码关闭连接。
  - 启动一个异步 `while` 循环：只要 WS 处于监控状态且 SSH 未断开，每隔 3 秒通过 `_monitorService.getSystemStatus(session)` 获取系统状态，并使用 `jsonEncode` 推送回前端。
  - 如果获取过程中抛出 `SocketException` 或 `SSHChannelOpenError`，或者 `session.client.isClosed` 为 true，则以状态码 `1011` (SSH Connection Lost) 主动关闭 WS 通道，并终止循环。

### 3. 更新后端路由
- **文件**: `lib/server/routes/api_routes.dart`
- **操作**: 
  - 移除原有的 `router.get('/api/monitor', systemController.monitor);`。
  - 添加新的 WS 路由映射：`router.get('/api/ws/monitor', systemController.wsMonitor);`。

### 4. 改造前端全局状态管理 (sshStore)
- **文件**: `ssh-tool-ui/src/stores/ssh.ts`
- **操作**:
  - 引入 `toast` 组件 (用于错误提示) 和 `MonitorResponse` 接口 (来自 `systemApi`)。
  - 新增响应式变量 `monitorData` 保存最新的系统监控数据。
  - 增加内部变量 `monitorWs` (WebSocket 实例), `wsReconnectTimer` (重连定时器), `isIntentionalClose` (标识是否为主动断开)。
  - 实现 `startMonitorWs()` 方法：
    - 连接到 `ws://<host>/api/ws/monitor?sessionId=<sessionId>`。
    - 监听 `onmessage`，解析 JSON 数据并更新 `monitorData`；如果是业务错误代码 (如 404 或 4004) 则触发会话失效逻辑。
    - 监听 `onclose`，如果是状态码 `4004` (会话未找到) 或 `1011` (SSH断开)，则触发 `handleSessionLost`（清空会话并弹出 Toast 提示）。否则如果在连接状态下非主动断开，则 3 秒后尝试重连。
  - 实现 `stopMonitorWs()` 方法：清理定时器、主动关闭 WS 连接、重置 `monitorData`。
  - 在 `setSession()` 中调用 `startMonitorWs()`，在 `clearSession()` 中调用 `stopMonitorWs()`。

### 5. 清理前端 API 定义
- **文件**: `ssh-tool-ui/src/api/system.ts`
- **操作**: 
  - 删除无用的 `getMonitorStatus` 函数。
  - 保留 `MonitorResponse` 类型定义供 `sshStore` 和视图组件使用。

### 6. 更新视图组件以使用全局状态
- **文件**: `ssh-tool-ui/src/components/os/SystemMonitor.vue` 和 `ssh-tool-ui/src/views/Dashboard.vue`
- **操作**:
  - 移除 `@tanstack/vue-query` 和 `systemApi` 的引入。
  - 删除相关的 `useQuery` 调用。
  - 将 `monitorData` 改为基于 `sshStore.monitorData` 的 `computed` 计算属性。视图的数据绑定将自动响应 WebSocket 推送的更新。
