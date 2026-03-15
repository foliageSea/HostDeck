# Plan: 封装统一响应 Result

本计划旨在对后端 `lib/server/controllers` 下的控制器进行重构，引入统一的 `Result` 响应结构，并同步修改前端 `http` 拦截器以适配新的响应格式。

## 1. 后端重构 (Backend Refactoring)

### 1.1 定义 `Result` 类
创建 `lib/server/models/result.dart`，定义统一的响应结构：
```dart
class Result<T> {
  final int code;
  final String message;
  final T? data;

  Result({required this.code, required this.message, this.data});

  Map<String, dynamic> toJson() => {
        'code': code,
        'message': message,
        'data': data,
      };

  static Result<T> success<T>(T? data, {String message = 'Success'}) {
    return Result(code: 200, message: message, data: data);
  }

  static Result<T> error<T>(int code, String message, {T? data}) {
    return Result(code: code, message: message, data: data);
  }
}
```

### 1.2 修改 Controllers
修改以下控制器，使其返回 `Result` 包装后的 JSON 响应（HTTP 状态码统一为 200，除非是流式响应）：

-   **`lib/server/controllers/auth_controller.dart`**
    -   `connect`: 返回 `Result.success({'sessionId': ..., 'connectionId': ...})`。
    -   错误处理：返回 `Result.error(500, e.toString())`。

-   **`lib/server/controllers/file_controller.dart`**
    -   `createSession`: 返回 `Result.success({'sessionId': ...})`。
    -   `listFiles`: 返回 `Result.success([...])`。
    -   `rename`, `mkdir`, `copy`, `deleteFile`, `uploadFile`: 将原来的字符串响应作为 data 返回，例如 `Result.success('Renamed')`。
    -   `readFile`, `batchDownload`: **保持原样**（返回二进制流，HTTP 200），不使用 `Result` 封装。
    -   错误处理：非流式接口统一返回 `Result.error(500, e.toString())`。

-   **`lib/server/controllers/system_controller.dart`**
    -   `status`: 返回 `Result.success({'status': 'running'})`。
    -   `monitor`: 返回 `Result.success(status)`。
    -   错误处理：将原来的 `_errorResponse` 逻辑改为返回 `Result.error(code, message)`。注意：原有的自定义错误码（如 `SESSION_NOT_FOUND`）将作为 `code` (如果改为 int) 或 `message` 的一部分。
        -   **策略调整**：为了兼容前端对 `SESSION_NOT_FOUND` 的检查，我们将使用 `code: 404` 来表示会话丢失，并在 `message` 中包含详细信息。

-   **`lib/server/controllers/terminal_controller.dart`**
    -   `createSession`: 返回 `Result.success({'sessionId': ...})`。
    -   `closeSession`: 返回 `Result.success('Session closed')`。
    -   WebSocket 处理器保持不变。

## 2. 前端适配 (Frontend Adaptation)

### 2.1 修改 HTTP 拦截器
修改 `ssh-tool-ui/src/lib/http.ts`：
-   **响应拦截器 (Response Interceptor)**：
    -   检查 `response.data` 是否包含 `code` 字段。
    -   如果 `code === 200`：解包 `response.data.data` 并返回，使其对上层调用透明。
    -   如果 `code !== 200`（且不是流式响应）：抛出错误，触发错误处理逻辑。
    -   保留对流式响应（Blob/ArrayBuffer）的直接透传。
-   **错误处理逻辑**：
    -   更新对 `SESSION_NOT_FOUND` 的检测逻辑，适配新的 `code` (404) 或 `message` 结构。

## 3. 验证 (Verification)
-   启动后端服务。
-   启动前端开发服务器。
-   测试主要功能：
    -   SSH 连接（Auth）。
    -   文件列表、上传、下载（File）。
    -   终端会话（Terminal）。
    -   系统监控（System）。
-   验证错误处理（如会话超时）。
