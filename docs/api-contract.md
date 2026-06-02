# API 合约

本文档说明前后端 API 的通用约定。具体业务接口见 `modules/*.md`。

## 统一 JSON 响应

普通 JSON API 使用 `lib/server/models/result.dart` 包装响应。

成功响应通常形如：

```json
{
  "code": 200,
  "message": "ok",
  "data": {}
}
```

失败响应通常形如：

```json
{
  "code": 500,
  "message": "error message",
  "data": null
}
```

注意：业务失败不一定对应 HTTP 非 2xx。当前普通 JSON API 中，`Result.fail(...)` 也可能返回 HTTP 200，前端通过 JSON `code` 判断业务状态。

## 前端解包行为

`host-deck-ui/src/lib/http.ts` 的响应拦截器会处理统一响应：

- `code === 200`：将 `response.data` 替换为后端 `data` 字段。
- `code !== 200`：创建并抛出 `AxiosError`。
- 非统一响应：原样返回。

因此 `src/api/*` 中的普通请求类型应直接描述解包后的 `data` 类型，而不是完整 `Result` 类型。

## 会话失效处理

当前前端会识别部分 SSH 会话失效错误：

- HTTP 状态为 `500` 或统一响应 `code` 为 `500`。
- 错误消息包含 `SSHChannelOpenError` 或 `SocketException`。

命中后，前端会提示用户并调用 `sshStore.clearSession()` 清理会话。

## WebSocket 路由

- `/api/ws/terminal`：终端会话通道。
- `/api/ws/monitor`：系统监控推送。
- `/api/ws/session`：SSH 会话状态推送。
- `/api/ws/runtime`：运行态会话推送。

WebSocket 路由不走统一 JSON API 解包。新增 WebSocket 时需要明确消息格式、连接生命周期、关闭语义和前端重连策略。

## 非统一响应场景

以下场景可能不走 `Result`：

- 文件下载。
- 批量下载。
- 镜像导出。
- 容器日志流或其他流式响应。
- 静态资源和 SPA fallback。
- WebSocket 握手与消息。

这些接口的前端封装应在 `src/api/*` 中明确 `responseType`、流式读取方式或二进制处理方式。

## 新增接口检查清单

新增或修改 API 时检查：

- `lib/server/routes/api_routes.dart` 是否注册路由。
- controller 是否只处理协议层逻辑。
- service/repository 是否承载业务和外部系统访问。
- 是否使用 `Result.ok` / `Result.fail`。
- `host-deck-ui/src/api/*` 类型是否描述解包后的数据。
- 调用方是否处理错误状态和 loading 状态。
- 涉及会话、密码、私钥、token 时是否避免日志泄露。
