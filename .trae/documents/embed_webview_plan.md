# 使用 flutter_inappwebview 内嵌前端 UI 计划

## 目标
将现有的 Flutter 宿主应用通过 `flutter_inappwebview` 改造为完全内嵌前端 Vue UI 的应用。同时区分开发环境（加载 Vite 调试服务）和生产环境（加载内置的 Shelf 静态服务）。

## 实施步骤

### 1. 初始化配置修改
- **文件**: `lib/main.dart`
- **操作**:
  - 引入 `package:flutter/foundation.dart` 以使用 `kDebugMode` 常量。
  - 引入 `package:flutter_inappwebview/flutter_inappwebview.dart`。
  - 修改 `main()` 函数为异步，并添加 `WidgetsFlutterBinding.ensureInitialized();`，这是初始化 WebView 插件所必需的。

### 2. 环境区分与 URL 路由策略
- **文件**: `lib/main.dart` (`_MyAppState`)
- **操作**:
  - 增加获取目标 URL 的逻辑：
    - 开发环境 (`kDebugMode == true`)：返回 `http://localhost:5173`（Vite 的默认热更新地址）。
    - 生产环境 (`kDebugMode == false`)：返回 `http://localhost:8080`（Flutter 后端 ServerService 启动的静态服务地址）。
  - 在生产环境中，必须确保 `_serverService.start()` 成功（即 `_isRunning == true`）之后再加载 WebView，避免页面白屏或 404。

### 3. UI 布局重构
- **文件**: `lib/main.dart` (`build` 方法)
- **操作**:
  - 移除现有的 `AppBar`，让前端 Vue UI (如 `Desktop.vue`) 接管整个应用的视窗，实现沉浸式体验。
  - 使用 `Stack` 或 `if-else` 条件渲染主视图：
    - **加载态**: 在服务启动前 (`_isRunning == false`)，显示一个全屏的居中加载动画 (`CircularProgressIndicator`)。
    - **主视图**: 服务启动后，渲染 `InAppWebView`。
    - **日志视图（可选/调试面板）**: 保留现有的日志和控制功能，可以将其放入一个 `Drawer`（抽屉）中，或者通过一个半透明的悬浮按钮 (`FloatingActionButton`) 来切换显示/隐藏日志面板，以便在排查问题时依然能看到 Dart 后端日志。

### 4. WebView 属性调优
- **文件**: `lib/main.dart`
- **操作**:
  - 为 `InAppWebView` 配置 `InAppWebViewSettings`：
    - `javaScriptEnabled: true` （开启 JS）
    - `transparentBackground: true` （允许透明背景，配合应用的暗色模式）
    - `disableContextMenu: true` （在生产环境中禁用默认的系统右键菜单，因为 Vue 前端实现了自定义右键菜单）
    - 开发环境下开启调试 (`isInspectable: kDebugMode`)。

### 5. 错误处理与重试机制
- **操作**:
  - 在 `InAppWebView` 的 `onLoadError` 回调中捕获加载失败（例如开发模式下忘了启动 Vite）。
  - 遇到错误时，在界面上显示错误信息，并提供一个“重试/刷新”按钮重新加载 URL。

## 预期结果
完成上述修改后，直接运行 Flutter 桌面端或移动端时，将直接看到 SSH Tool 的前端 UI 界面。开发时享有 Vite 的热更新，打包发布后则内网自闭环提供完整服务，体验与原生桌面级应用一致。