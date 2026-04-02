# SSH Tool

这是一个基于 Dart/Flutter（后端）和 Vue 3（前端 UI）构建的跨平台 SSH 工具。它提供了一个现代化的 Web 界面，用于管理 SSH 连接、文件传输和系统监控。

项目现在支持两种运行方式：
- Flutter 桌面壳模式（原有模式）
- 纯 Dart B/S 模式（可打包为二进制并运行在 Docker 中）

## ✨ 功能特性

### 🖥️ 终端 (Terminal)
- **独立会话**: 支持多标签页独立会话，利用 SSH 复用技术。
- **xterm.js 集成**: 提供完整的终端体验，支持颜色和快捷键。
- **浮动复制按钮**: 选中文本后自动弹出复制按钮，优化操作体验。

### 📂 文件管理器 (File Manager)
- **SFTP 支持**: 独立的 SFTP 会话，不阻塞终端操作。
- **视图切换**: 支持网格 (Grid) 和列表 (List) 视图。
- **文件操作**: 支持文件/文件夹的上传、下载、重命名、删除等操作。
- **媒体预览**: 
  - 图片直接预览。
  - 视频支持使用 `xgplayer` 在线播放。
- **文本编辑**: 内置 Monaco Editor，支持语法高亮和字体设置。
- **收藏夹**: 快速访问常用目录。

### 📊 系统监控 (Dashboard)
- **实时监控**: 可视化展示 CPU、内存和磁盘使用率 (基于 ECharts)。
- **顶部栏小组件**: 实时显示关键系统指标。
- **暗色模式**: 全局暗色模式支持，适配所有图表和 UI 组件。

### 🎨 UI/UX
- **现代化设计**: 基于 Shadcn Vue 和 Tailwind CSS。
- **动态背景**: 桌面和登录页支持视频背景。
- **自定义滚动条**: 美观的自动隐藏式滚动条。

## 🛠️ 技术栈

### Backend (Flutter)
- **Dart**: 编程语言。
- **dartssh2**: SSH 客户端实现。
- **shelf**: Web 服务器框架。
- **sqlite3**: 本地数据存储。

### Frontend (Vue 3)
- **Vue 3**: 前端框架。
- **Vite**: 构建工具。
- **TypeScript**: 静态类型支持。
- **Pinia**: 状态管理。
- **Shadcn Vue & Tailwind CSS**: UI 组件库。
- **xterm.js**: 终端模拟器。
- **Monaco Editor**: 代码编辑器。
- **TanStack Query**: 数据请求管理。

## 🚀 快速开始

### 前置要求
- [Flutter SDK](https://flutter.dev/docs/get-started/install)
- [Node.js](https://nodejs.org/) (推荐使用 pnpm)

### 1. 启动后端 (Flutter 壳模式)

后端服务负责建立 SSH 连接并提供 API 接口。

```bash
# 获取依赖
flutter pub get

# 启动 Windows 应用 (或 macos/linux)
flutter run -d windows
```
服务默认运行在 `http://localhost:8080`。

### 2. 启动后端 (纯 Dart B/S 模式)

```bash
# 获取依赖
flutter pub get

# 启动服务（显式指定前端 dist 目录）
dart run bin/server.dart --host 0.0.0.0 --port 8080 --web-dir ssh-tool-ui/dist
```

可选参数：
- `--data-dir <path>`：指定 sqlite 与配置文件存储目录
- `--web-dir <path>`：指定静态前端资源目录，不传时会尝试从可执行文件旁 `../web` 自动发现

### 3. 启动前端 (Vue)

前端界面通过 API 与后端交互。

```bash
cd ssh-tool-ui

# 安装依赖
pnpm install

# 启动开发服务器
pnpm dev
```
访问控制台输出的地址 (通常是 `http://localhost:5173`) 即可使用。

## 📦 打包纯 Dart 服务

### 本机构建（当前平台）

Linux/macOS:
```bash
scripts/build_server.sh
```

Windows PowerShell:
```powershell
./scripts/build_server.ps1
```

构建结果位于 `build/server/bundle/`：
- 可执行文件：`build/server/bundle/bin/server(.exe)`
- 动态库：`build/server/bundle/lib/`
- 前端静态资源：`build/server/bundle/web/`

运行示例：
```bash
./build/server/bundle/bin/server --host 0.0.0.0 --port 8080 --web-dir ./build/server/bundle/web
```

## 🐳 Docker 构建与运行

```bash
docker build -t ssh-tool:local .
docker run --rm -p 8080:8080 -v ssh-tool-data:/data ssh-tool:local
```

容器默认启动参数：
- `--host 0.0.0.0`
- `--port 8080`
- `--web-dir /app/web`
- `--data-dir /data`

## 📂 项目结构

```
ssh_tool/
├── lib/                 # Flutter 后端源码
│   ├── server/          # 服务器逻辑 (API, Services)
│   └── main.dart        # 入口文件
├── ssh-tool-ui/         # Vue 前端源码
│   ├── src/
│   │   ├── components/  # UI 组件
│   │   ├── views/       # 页面视图
│   │   └── stores/      # Pinia 状态管理
│   └── package.json
├── pubspec.yaml         # Flutter 依赖配置
└── README.md            # 项目说明
```

## 📄 开源协议

本项目采用 [MIT License](LICENSE) 开源协议。
