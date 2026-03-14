# 服务状态监控、启停和日志输出功能实现计划

## 1. 目标
为 `main.dart` 提供的 Flutter 桌面/服务端宿主应用增加以下功能：
- **服务状态监控**：实时显示当前 HTTP 服务的运行状态（运行中 / 已停止）。
- **服务启停控制**：提供 UI 按钮以手动启动和停止后台服务。
- **实时日志输出**：捕获服务的启动日志以及所有 HTTP 请求日志，并在 UI 上滚动显示。

## 2. 实施步骤

### 步骤 1：改造 `ServerService` 以支持日志回调和状态查询
**文件：** `lib/server/server_service.dart`
- **添加状态属性**：增加 `bool get isRunning => _server != null;` 用于判断服务是否正在运行。
- **支持日志回调**：
  - 修改 `start` 方法签名，增加命名参数：`{void Function(String)? onLog}`。
  - 在初始化 `shelf` 的 `Pipeline` 时，为 `logRequests` 中间件传入自定义 `logger`：
    ```dart
    .addMiddleware(logRequests(logger: (message, isError) {
      if (onLog != null) onLog(message);
      else print(message);
    }))
    ```
  - 将原有的 `print('Server running...')` 修改为通过 `onLog` 输出。
- **完善停止逻辑**：在 `stop` 方法中，不仅关闭 `_server`，还需要将其置为 `null`，以正确反映服务已停止的状态。

### 步骤 2：重构 `main.dart` UI 和状态管理
**文件：** `lib/main.dart`
- **状态管理**：
  - 在 `_MyAppState` 中添加状态变量：
    - `bool _isRunning = false;` （服务当前状态）
    - `List<String> _logs = [];` （日志数据记录）
    - `final ScrollController _scrollController = ScrollController();` （控制日志列表自动滚动）
- **功能方法**：
  - `_addLog(String message)`：将新日志格式化（如增加时间戳）并存入 `_logs`，然后调用 `setState`，同时利用 `_scrollController` 滚动到最底部。
  - `_startServer()`：调用 `_serverService.start(onLog: _addLog)`，启动成功后更新 `_isRunning` 状态。
  - `_stopServer()`：调用 `_serverService.stop()`，并在完成后更新 `_isRunning` 状态，并记录停止日志。
  - `_clearLogs()`：清空当前日志列表。
- **UI 构建**：
  - **头部面板**：包含状态指示器（如绿色/红色圆点和文本）、“启动”、“停止”、“清空日志”按钮。
  - **日志显示区**：使用 `Expanded` 和 `Container` 包裹一个 `ListView.builder`，提供黑色背景的控制台风格日志视图，并支持文本选择 (`SelectableText`)。
  - 启动应用时在 `initState` 中默认调用一次 `_startServer()`，确保行为和之前一致（启动即运行）。

## 3. 预期效果
- 用户可以直接在宿主应用的界面上看到服务是否在正常运行。
- 用户可以手动干预服务的启停。
- 所有通过该服务产生的请求日志都能直观地显示在应用界面下方，方便调试和监控。
