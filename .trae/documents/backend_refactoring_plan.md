# 后端分层架构拆分计划

我们将把现有的 `lib/server` 目录下的代码重构为标准的分层架构。目标是解耦控制器、服务和数据访问逻辑，提高代码的可维护性和可扩展性。

## 1. 目标架构

采用 **Controller-Service-Repository** 三层架构，并按层级分组：

- **Controllers (`lib/server/controllers/`)**: 处理 HTTP 请求，解析参数，调用 Service，返回响应。
- **Services (`lib/server/services/`)**: 处理业务逻辑（如监控数据解析、会话管理）。
- **Repositories (`lib/server/repositories/`)**: 处理底层数据访问（SSH 命令执行、SFTP 操作）。
- **Models (`lib/server/models/`)**: 数据模型和 DTO（数据传输对象）。
- **Routes (`lib/server/routes/`)**: 定义路由配置。

## 2. 详细步骤

### 第一步：创建目录结构
在 `lib/server` 下创建以下目录：
- `controllers`
- `services`
- `repositories`
- `models`
- `routes`

### 第二步：定义数据模型 (Models)
创建以下模型文件：
- `lib/server/models/ssh_session.dart`: 封装 SSH 会话状态（ID, Client, Shell, Stream）。
- `lib/server/models/system_status.dart`: 定义系统监控数据结构（CPU, RAM, Disk）。
- `lib/server/models/file_item.dart`: 定义文件信息结构。

### 第三步：实现 Repository 层
创建 `lib/server/repositories/ssh_repository.dart`：
- 封装底层的 `dartssh2` 操作。
- 方法：`exec`, `listFiles`, `readFile`, `writeFile`, `delete`。
- 将原 `SshSession` 中的 `exec` 等方法迁移至此，或在此调用底层 API。

### 第四步：实现 Service 层
- **`lib/server/services/ssh_service.dart`**:
  - 管理全局会话列表 (`_sessions`)。
  - 处理连接建立 (`connect`) 和断开 (`closeSession`)。
  - 提供 `getSession` 方法。
- **`lib/server/services/monitor_service.dart`**:
  - 调用 `ssh_repository.exec` 获取系统信息。
  - 解析 `uptime`, `free`, `df` 的输出并返回 `SystemStatus` 对象。
- **`lib/server/services/file_service.dart`**:
  - 调用 `ssh_repository` 进行文件操作。
  - 处理业务逻辑（如路径校验等）。

### 第五步：实现 Controller 层
- **`lib/server/controllers/auth_controller.dart`**: 处理 `/api/connect`。
- **`lib/server/controllers/system_controller.dart`**: 处理 `/api/status`, `/api/monitor`。
- **`lib/server/controllers/file_controller.dart`**: 处理 `/api/files/*`。
- **`lib/server/controllers/terminal_controller.dart`**: 处理 `/socket.io` WebSocket 连接。

### 第六步：配置路由 (Routes)
创建 `lib/server/routes/api_routes.dart`：
- 定义 `Router`。
- 将路由路径映射到对应的 Controller 方法。

### 第七步：重构 ServerService
修改 `lib/server/server_service.dart`：
- 移除所有业务逻辑和路由处理。
- 仅保留 `HttpServer` 的启动和停止逻辑。
- 引用 `api_routes.dart` 获取路由 handler。

## 3. 验证计划
- 启动重构后的服务。
- 使用 HTTP 客户端（或 curl）测试 `/api/status` 确保服务运行。
- 测试 `/api/connect` 建立连接。
- 测试 `/api/monitor` 获取数据。
- 测试文件操作接口。
- 测试 WebSocket 终端连接。
