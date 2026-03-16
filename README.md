# SSH Tool

这是一个基于 Flutter (后端/Host) 和 Vue 3 (前端 UI) 构建的跨平台 SSH 工具。它提供了一个现代化的 Web 界面，用于管理 SSH 连接、文件传输和系统监控。

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

### 1. 启动后端 (Flutter)

后端服务负责建立 SSH 连接并提供 API 接口。

```bash
# 获取依赖
flutter pub get

# 启动 Windows 应用 (或 macos/linux)
flutter run -d windows
```
服务默认运行在 `http://localhost:8080`。

### 2. 启动前端 (Vue)

前端界面通过 API 与后端交互。

```bash
cd ssh-tool-ui

# 安装依赖
pnpm install

# 启动开发服务器
pnpm dev
```
访问控制台输出的地址 (通常是 `http://localhost:5173`) 即可使用。

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
