# SSH Web工具规范 (Create SSH Tool)

## 为什么 (Why)
目前，管理多个服务器通常需要分散的工具来进行终端访问、文件传输（SFTP）和编辑配置文件。用户需要一个统一的、跨平台的、基于Web（B/S架构）的解决方案，结合现代、直观的仿MacOS界面。此外，未来还需要支持Docker管理扩展。

## 变更内容 (What Changes)
- **项目结构**:
  - **后端 (宿主)**: 使用 Flutter 创建的项目，作为应用入口和服务器宿主。
  - **前端 (Web UI)**: 使用 Vue 3 创建的项目，构建为静态资源。
- **后端服务 (Flutter)**:
  - 在 Flutter 应用启动时，启动基于 `shelf` 的 HTTP 和 WebSocket 服务。
  - 使用 `dartssh2` 实现安全的 SSH 连接处理。
  - 使用 `shelf_web_socket` 处理实时终端流。
  - 实现 SFTP 包装器和系统监控数据收集。
  - (可选) Flutter 窗口可显示服务器状态或日志，主要功能通过 Web 浏览器访问。
- **前端应用 (Vue 3)**:
  - **UI框架**: Vue 3 + Tailwind CSS，仿照 MacOS 风格。
  - **终端**: `xterm.js`。
  - **文件管理 & 编辑器**: 图形化文件管理和 `monaco-editor` 集成。
  - **监控**: 可视化图表。
- **Docker扩展**: 后端架构设计预留 Docker 管理接口。

## 影响 (Impact)
- **新功能**: 用户运行 Flutter 应用后，通过浏览器访问本地端口即可管理服务器。
- **受影响代码**: 全新项目结构。
- **依赖项**:
  - Flutter: `shelf`, `shelf_router`, `shelf_web_socket`, `dartssh2`, `shelf_static` (用于服务 Vue 构建产物).
  - Vue: `vue`, `xterm`, `monaco-editor`, `echarts`.

## 新增需求 (ADDED Requirements)
### 需求: Flutter 启动的服务端
系统应为一个 Flutter 应用程序，启动后在本地端口监听 HTTP 请求。

#### 场景: 启动应用
- **当** 用户运行 Flutter 应用。
- **那么** 应用启动 Shelf 服务器，并显示访问地址（如 http://localhost:8080）。

### 需求: 基于Web的SSH终端
通过浏览器访问上述地址，提供 SSH 终端功能。

#### 场景: 连接
- **当** 用户在 Web 界面输入 SSH 信息。
- **那么** Flutter 后端建立 SSH 连接并通过 WebSocket 转发数据。

### 需求: 文件管理 & 监控
(同前，由 Flutter 后端处理业务逻辑)

### 需求: 仿MacOS UI
(同前，Web 界面风格)
