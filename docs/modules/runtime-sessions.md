# 运行态会话模块

运行态会话模块用于查看当前服务内维护的 SSH、终端、文件、Docker 等运行态会话信息，主要用于观察和调试。

## 代码入口

后端：

- `lib/server/controllers/runtime_controller.dart`
- `lib/server/services/ssh_service.dart`

前端：

- `ssh-tool-ui-next/src/api/runtime.ts`
- `ssh-tool-ui-next/src/views/RuntimeSessions/index.vue`

## API 与通道

- `GET /api/runtime/sessions`：获取运行态会话列表。
- `GET /api/ws/runtime`：运行态会话 WebSocket 推送。

## 开发要点

- 该模块应只暴露调试和观察所需信息，不应泄露凭据。
- 会话 ID、类型、状态、创建时间、活动时间等字段应保持稳定，便于前端展示。
- 新增运行态资源类型时，应同步 runtime 输出和前端展示逻辑。
- WebSocket 推送应在连接关闭时释放定时器或订阅。
