# Plan: 简化 Result 响应构建

本计划旨在通过在 `Result` 类中添加静态辅助方法，简化 Controller 层构建 JSON 响应的代码，消除重复的 `jsonEncode` 和 `headers` 设置。

## 1. 修改 Result 类 (Update Result Class)

修改 `lib/server/models/result.dart`：
1.  导入 `dart:convert` 和 `package:shelf/shelf.dart`。
2.  添加静态方法 `ok` 和 `fail`，用于直接生成 `shelf.Response` 对象。

```dart
import 'dart:convert';
import 'package:shelf/shelf.dart';

class Result<T> {
  // ... existing fields and constructor ...

  // ... existing toJson method ...

  // ... existing static factory methods (success, error) ...

  /// Helper to create a successful JSON response
  static Response ok<T>(T? data, {String message = 'Success'}) {
    return Response.ok(
      jsonEncode(Result.success(data, message: message).toJson()),
      headers: {'content-type': 'application/json'},
    );
  }

  /// Helper to create a failure JSON response (HTTP 200 with error code)
  static Response fail<T>(int code, String message, {T? data}) {
    return Response.ok(
      jsonEncode(Result.error(code, message, data: data).toJson()),
      headers: {'content-type': 'application/json'},
    );
  }
}
```

## 2. 重构 Controllers (Refactor Controllers)

遍历 `lib/server/controllers` 下的所有控制器，使用新的静态方法替换旧的响应构建模式。

### 2.1 AuthController
-   文件：`lib/server/controllers/auth_controller.dart`
-   修改：
    -   `connect`: 使用 `Result.ok(...)` 和 `Result.fail(...)`。

### 2.2 FileController
-   文件：`lib/server/controllers/file_controller.dart`
-   修改以下方法，使用简化写法：
    -   `createSession`
    -   `listFiles`
    -   `writeFile`
    -   `uploadFile`
    -   `rename`
    -   `mkdir`
    -   `copy`
    -   `deleteFile`
-   注意：`readFile` 和 `batchDownload` 保持原样（流式响应）。

### 2.3 SystemController
-   文件：`lib/server/controllers/system_controller.dart`
-   修改：
    -   `status`
    -   `monitor`

### 2.4 TerminalController
-   文件：`lib/server/controllers/terminal_controller.dart`
-   修改：
    -   `createSession`
    -   `closeSession`

## 3. 验证 (Verification)
-   确保代码编译通过。
-   无需修改前端代码，因为响应格式保持不变（JSON 结构一致）。
