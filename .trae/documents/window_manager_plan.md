# 窗口管理器与自绘标题栏集成计划 (window_manager)

## 目标
使用 `window_manager` 插件来控制 Flutter 桌面端的窗口大小，并隐藏原生标题栏，替换为在 Flutter 内部自绘的自定义标题栏。

## 实施步骤

### 1. 初始化 `window_manager` 与配置窗口属性
- **文件:** `lib/main.dart`
- **操作:** 
  - 在文件顶部引入 `package:window_manager/window_manager.dart`。
  - 修改 `main()` 函数为 `async`。
  - 在 `runApp` 之前调用 `await windowManager.ensureInitialized();`。
  - 创建 `WindowOptions` 实例：
    - 设置 `size` (例如 1024x768) 和 `minimumSize` (例如 800x600)。
    - 设置 `center: true` 让窗口居中。
    - 设置 `titleBarStyle: TitleBarStyle.hidden` 以隐藏系统原生标题栏。
  - 调用 `windowManager.waitUntilReadyToShow` 并在回调中展示并聚焦窗口。

### 2. 构建自绘窗口标题栏 (Custom Title Bar)
- **文件:** `lib/main.dart`
- **操作:** 
  - 在 `_MyAppState` 的 `build` 方法中，将 `Scaffold` 的 `body` 改造为 `Column` 布局。
  - 顶部增加一个固定高度（例如 40 像素）的自定义标题栏区域。
  - 使用 `window_manager` 提供的 `DragToMoveArea` 组件包裹整个标题栏区域，以支持拖拽移动窗口的功能。
  - 标题栏内容包括：
    - **左侧:** 应用 Logo 或标题文字（例如 "SSH Tool"）。
    - **中间:** 占据剩余空间的空白区域（`Expanded`）。
    - **右侧:** 三个窗口控制按钮（最小化、最大化/还原、关闭）。
  - 为控制按钮绑定对应的 API：
    - 最小化: `windowManager.minimize()`
    - 最大化/还原: `windowManager.isMaximized()` 结合 `windowManager.maximize()` 和 `windowManager.unmaximize()`
    - 关闭: `windowManager.close()`

### 3. 适配现有 WebView 和悬浮 UI
- **文件:** `lib/main.dart`
- **操作:** 
  - 将原本位于 `SafeArea` > `Stack` 中的主要内容（包含 `InAppWebView` 以及悬浮日志窗口）包裹在一个 `Expanded` 中，放在自定义标题栏下方。
  - 确保日志窗口和悬浮按钮不会与自定义标题栏发生遮挡冲突。

### 4. 主题适配与代码规范
- **文件:** `lib/main.dart`
- **操作:**
  - 自绘标题栏的背景色、文字颜色和图标颜色需跟随系统的明暗主题 (`Theme.of(context).colorScheme.background` / `brightness` 等) 自动切换。
  - 根据用户的要求，为新增的方法和组件添加中文格式的**函数级别注释**。

## 预期结果
启动应用后，将不再显示 Windows 11 原生的白色/黑色边框标题栏。应用将以设定的默认尺寸居中启动，顶部拥有与应用整体 UI 风格一致的自定义标题栏，并且支持拖拽移动、双击放大（可通过逻辑实现）及完整的窗口控制按钮。
