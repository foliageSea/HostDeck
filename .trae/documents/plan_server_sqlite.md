# 计划：将服务器信息保存到后端 SQLite

本计划概述了在后端（Dart）使用 SQLite 实现服务器连接信息持久化存储的步骤，并更新前端（Vue）以利用此新功能。

## 第一阶段：后端实现 (Dart)

### 1. 依赖管理

* `sqlite3` 依赖已存在于 `pubspec.yaml` 中，且支持 Windows，无需额外添加依赖。

* 确保 `path` 和 `path_provider` 可用（已验证）。

### 2. 数据库基础设施

* **创建** **`lib/server/services/database_service.dart`**：

  * 初始化 `sqlite3` 数据库连接。

  * 使用 `path_provider` 将数据库文件存储在持久化位置（如 `ApplicationSupportDirectory`）。

  * 实现迁移系统以创建 `servers` 表。

  * **表结构 (`servers`)**：

    * `id` (INTEGER PRIMARY KEY AUTOINCREMENT)

    * `name` (TEXT)

    * `host` (TEXT)

    * `port` (INTEGER)

    * `username` (TEXT)

    * `password` (TEXT) - *注意：在实际应用中应加密存储，但在本任务中暂存为文本。*

    * `privateKey` (TEXT)

    * `createdAt` (INTEGER)

### 3. 服务器模型

* **创建** **`lib/server/models/server_config.dart`**：

  * 定义 `ServerConfig` 类，包含 `fromJson` 和 `toJson` 方法。

### 4. 服务器仓库

* **创建** **`lib/server/repositories/server_repository.dart`**：

  * 实现 `getAllServers()`: 返回 `List<ServerConfig>`。

  * 实现 `getServer(int id)`: 返回 `ServerConfig?`。

  * 实现 `addServer(ServerConfig server)`: 返回 `ServerConfig`（带有新生成的 ID）。

  * 实现 `updateServer(ServerConfig server)`: 返回 `bool`（是否成功）。

  * 实现 `deleteServer(int id)`: 返回 `bool`（是否成功）。

### 5. 服务器控制器

* **创建** **`lib/server/controllers/server_controller.dart`**：

  * `list(Request request)`: GET /api/servers

  * `create(Request request)`: POST /api/servers

  * `update(Request request, String id)`: PUT /api/servers/<id>

  * `delete(Request request, String id)`: DELETE /api/servers/<id>

### 6. 路由注册

* **更新** **`lib/server/routes/api_routes.dart`**：

  * 将 `ServerController` 的路由挂载到 `/api/servers` 下。

### 7. 服务集成

* **更新** **`lib/server/server_service.dart`**：

  * 初始化 `DatabaseService`。

  * 使用数据库初始化 `ServerRepository`。

  * 使用仓库初始化 `ServerController`。

  * 将控制器传递给 `ApiRoutes`。

## 第二阶段：前端实现 (Vue)

### 1. API 客户端

* **创建** **`ssh-tool-ui/src/api/server.ts`**：

  * 实现 `serverApi` 对象，包含调用后端接口的方法。

### 2. Store 更新

* **更新** **`ssh-tool-ui/src/stores/ssh.ts`**：

  * 移除 `localStorage` 逻辑，改为 API 调用。

  * 添加 `fetchServers()` action 以在启动时加载服务器列表。

  * 更新 `addServer`, `removeServer`, `updateServer` 方法以使用 `serverApi`。

  * 移除前端生成 ID 的逻辑（交由后端处理）。

### 3. UI 集成

* **更新** **`ssh-tool-ui/src/components/os/LoginScreen.vue`**：

  * 在组件挂载时调用 `sshStore.fetchServers()`。

  * 确 UI 正确处理服务器操作的异步状态。

## 验证

* 重启应用程序。

* 在登录界面添加一个新的服务器。

* 验证服务器是否出现在列表中。

* 再次重启应用程序以验证持久化是否生效。

* 检查后端日志是否有 SQL 执行记录（可选）。

