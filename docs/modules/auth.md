# SSH 连接与认证模块

认证模块负责建立、断开和维护当前 SSH 连接。项目没有传统用户账号体系，前端登录本质是创建 SSH 会话。

## 代码入口

后端：

- `lib/server/features/auth/auth_controller.dart`
- `lib/server/core/ssh/ssh_service.dart`
- `lib/server/core/ssh/ssh_repository.dart`
- `lib/server/core/ssh/ssh_session.dart`
- `lib/server/core/ssh/ssh_operation_limiter.dart`

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

## 连接生命周期与回收

SSH 连接由 [SshService](../../lib/server/core/ssh/ssh_service.dart) 统一托管，回收策略分三层，任何一层都不能用「某个对象是否存在」来判断：

1. **通道租约**：状态 WS（`/api/ws/session`）、终端 WS、监控 WS 和 AI Agent run 在开始时 `attachLease`，结束时 `detachLease`。心跳超时或 WS 关闭**只释放租约**，不再直接断开 SSH —— 浏览器 WebSocket 可能静默失效（TCP 仍 ESTABLISHED 但收不到数据），一次抖动不应该拆掉整条连接。
2. **可见活动**：收到状态 WS 的 `ping`、带 `connectionId` 的任意 HTTP 请求、终端输入/输出、SSH 操作开始与结束都会调用 `SshService.touch`。空闲回收器每 15 秒扫描一次，只有在「没有租约 + 超过 `channelIdleGrace`（120 秒）没有活动 + 没有进行中的 SSH 操作」时才真正断开。
3. **链路存活**：记录 SSH socket 最后一次收到字节的时间。dartssh2 每 10 秒发送 keep-alive 全局请求，正常链路必然有回包，所以沉默超过 `socketSilenceTimeout`（3 分钟）就判定半开连接并关闭，避免等 TCP 重传超时（约 15 分钟）。

新增长连接能力（SSE、隧道、长时间任务）时，应按同样方式持有租约或在数据往返时 `touch`，否则会被空闲回收器当成已废弃会话。

## 会话失效

前端 HTTP 拦截器会识别包含 `SSHChannelOpenError` 或 `SocketException` 的部分错误，并清理当前会话。新增接口如果依赖 SSH 会话，应确保错误信息能被调用方正确处理。

## 安全要求

- 不要记录密码、私钥、token。
- 不要把完整连接参数写入普通日志。
- 前端持久化时只保存必要的非敏感信息。
- 认证失败时返回可诊断但不泄露凭据的错误消息。
