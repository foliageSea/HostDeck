# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

SSH Tool 是一个跨平台的SSH客户端工具，使用Flutter作为桌面应用框架和Vue.js作为前端UI框架。该工具允许用户连接远程SSH服务器，进行终端操作、文件管理、系统监控等功能。

项目由两部分组成：
1. 使用Flutter/Dart开发的后端服务（`lib/` 目录）
2. 使用Vue.js开发的前端UI（`ssh-tool-ui/` 目录）

## 架构

### 后端 (Dart/Flutter)

- **主程序**: `lib/main.dart` - Flutter应用入口，负责启动窗口和内置Web服务器
- **服务层**: `lib/server/services/` - 核心业务逻辑，包括SSH连接、文件操作、系统监控等
- **控制器**: `lib/server/controllers/` - API路由处理逻辑
- **模型**: `lib/server/models/` - 数据模型定义
- **存储库**: `lib/server/repositories/` - 数据持久化操作
- **工具类**: `lib/utils/` - 辅助工具函数

### 前端 (Vue.js)

- **应用入口**: `ssh-tool-ui/src/App.vue` - 主应用组件
- **视图**: `ssh-tool-ui/src/views/` - 主要页面视图
  - `Dashboard.vue` - 控制面板
  - `Files.vue` - 文件管理器
  - `Terminal.vue` - 终端模拟器
  - `TextEditor.vue` - 文本编辑器
  - `MediaViewer.vue` - 媒体查看器
- **组件**: `ssh-tool-ui/src/components/` - UI组件
- **存储**: `ssh-tool-ui/src/stores/` - Pinia状态管理

## 开发工作流

### 后端开发

1. **启动Flutter开发服务**:
   ```bash
   flutter run -d windows # 或 macos, linux
   ```

2. **编译发布版本**:
   ```bash
   flutter build windows # 或 macos, linux
   ```

### 前端开发

1. **安装依赖**:
   ```bash
   cd ssh-tool-ui
   npm install
   ```

2. **启动开发服务器**:
   ```bash
   cd ssh-tool-ui
   npm run dev
   ```

3. **构建前端资源**:
   ```bash
   cd ssh-tool-ui
   npm run build
   ```

## 关键功能实现

### SSH连接

SSH连接由`lib/server/services/ssh_service.dart`实现，使用`dartssh2`包处理底层连接。每个SSH连接创建一个`SSHClient`实例，可以创建多个会话（shell或SFTP）。

### 文件操作

文件操作由`lib/server/services/file_service.dart`和`lib/server/controllers/file_controller.dart`实现。支持文件浏览、上传、下载、删除等操作。

### 终端模拟

终端功能由`lib/server/controllers/terminal_controller.dart`实现后端部分，前端使用`@xterm/xterm`库进行终端模拟。

### 系统监控

系统监控功能由`lib/server/services/monitor_service.dart`实现，通过SSH执行系统命令获取服务器状态信息。

## 构建注意事项

1. 前端资源在构建Flutter应用之前需要先构建（`npm run build`）
2. 构建的前端资源通过`lib/utils/asset_extractor.dart`在运行时解压到临时目录供内置服务器使用
3. 默认服务端口为8080，可以通过设置界面修改