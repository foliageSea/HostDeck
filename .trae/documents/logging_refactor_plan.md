# 日志改造计划 (Logging Refactor Plan)

## 目标
使用 Dart 官方的 `logging` 包替换目前项目中零散的 `print` 和回调形式（`onLog`）的日志记录。统一日志的输出格式，并确保日志能够同时输出到控制台（Console）和应用内的 UI 日志面板中。

## 改造范围
涉及以下文件：
1. `lib/main.dart`
2. `lib/server/server_service.dart`
3. `lib/utils/app_settings.dart`
4. `lib/server/services/database_service.dart`
5. `lib/server/controllers/auth_controller.dart`
6. `lib/utils/asset_extractor.dart`

## 实施步骤

### 步骤 1: 全局日志配置 (`lib/main.dart`)
- **引入依赖**：导入 `package:logging/logging.dart`。
- **根日志监听**：
  - 在 `_MyAppState` 中声明 `StreamSubscription<LogRecord>? _logSubscription;`。
  - 在 `initState` 中配置全局日志级别：`Logger.root.level = Level.ALL;`。
  - 监听 `Logger.root.onRecord`：
    - 将日志格式化为：`[INFO] LoggerName: Message`，如果有 error/stackTrace 则一并追加。
    - 使用 `debugPrint` 将格式化后的日志输出到控制台。
    - 调用原有的 `_addLog` 方法，将日志追加到 UI 日志列表中。
- **资源释放**：在 `dispose` 方法中调用 `_logSubscription?.cancel()`，防止内存泄漏。
- **替换内部打印**：
  - 为 `main.dart` 自身创建一个 `final _log = Logger('MyApp');`。
  - 替换 `_addLog('System: ...')` 和 WebView 的直接日志输出，改为 `_log.info(...)` 或 `_log.severe(...)`。

### 步骤 2: 移除 `onLog` 回调机制 (`lib/server/server_service.dart`)
- **引入依赖**：导入 `package:logging/logging.dart`。
- **定义 Logger**：声明 `final _log = Logger('ServerService');`。
- **修改方法签名**：从 `start({void Function(String)? onLog})` 中移除 `onLog` 参数。
- **替换日志调用**：
  - 将 `onLog(...)` 和 `print(...)` 替换为 `_log.info(...)` 或 `_log.severe(...)`。
  - 更新 `logRequests` 中间件的 `logger` 回调：
    ```dart
    logger: (message, isError) {
      if (isError) {
        _log.severe(message);
      } else {
        _log.info(message);
      }
    }
    ```

### 步骤 3: 替换项目其他模块中的 `print` 调用
- **`lib/utils/app_settings.dart`**：
  - 添加 `final _log = Logger('AppSettings');`。
  - 将 `print('Settings file path: ...')` 替换为 `_log.info(...)`。
- **`lib/server/services/database_service.dart`**：
  - 添加 `final _log = Logger('DatabaseService');`。
  - 将 `print('Database path: ...')` 替换为 `_log.info(...)`。
- **`lib/server/controllers/auth_controller.dart`**：
  - 添加 `final _log = Logger('AuthController');`。
  - 将 `print('Connect Error: $e');` 替换为 `_log.severe(...)`。
- **`lib/utils/asset_extractor.dart`**：
  - 添加 `final _log = Logger('AssetExtractor');`。
  - 替换各种 `print(...)` 为 `_log.info(...)`，报错分支改为 `_log.severe(...)`。

## 预期结果
- 项目中不再有零散的 `print`，统一使用 `Logger` 实例。
- 无论代码在何处记录日志，UI 界面的 `Host Logs` 都能捕获并显示，且自带级别标识和统一的时间戳。
- 后台终端能够输出同样标准化的日志信息，便于调试排查。