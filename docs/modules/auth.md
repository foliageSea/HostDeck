# SSH 连接与认证模块

认证模块负责建立、断开和维护当前 SSH 连接。项目没有传统用户账号体系，前端登录本质是创建 SSH 会话。

## 代码入口

后端：

- `lib/server/controllers/auth_controller.dart`
- `lib/server/services/ssh_service.dart`
- `lib/server/repositories/ssh_repository.dart`
- `lib/server/models/ssh_session.dart`
- `lib/server/models/ssh_operation_limiter.dart`

前端：

- `host-deck-ui/src/api/auth.ts`
- `host-deck-ui/src/stores/ssh.ts`
- `host-deck-ui/src/components/os/LoginScreen.vue`
- `host-deck-ui/src/lib/http.ts`

## API

- `POST /api/connect`：创建 SSH 连接。
- `DELETE /api/connect`：断开当前 SSH 连接。

## 开发要点

- controller 负责解析连接参数并调用 `SshService`。
- `SshService` 是运行态 SSH 会话的核心管理者，其它模块通过它获取当前连接状态或创建通道。
- `SshRepository` 封装底层 SSH 行为，业务层不应直接散落 dartssh2 调用。
- 前端 `ssh` store 保存连接状态、主机、端口、用户名等用于 UI 的运行态信息。
- 路由守卫会在 `requiresAuth` 页面中检查 `sshStore.isConnected`。

## 会话失效

前端 HTTP 拦截器会识别包含 `SSHChannelOpenError` 或 `SocketException` 的部分错误，并清理当前会话。新增接口如果依赖 SSH 会话，应确保错误信息能被调用方正确处理。

## 安全要求

- 不要记录密码、私钥、token。
- 不要把完整连接参数写入普通日志。
- 前端持久化时只保存必要的非敏感信息。
- 认证失败时返回可诊断但不泄露凭据的错误消息。
