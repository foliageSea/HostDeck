# HostDeck 访问认证

HostDeck 的访问认证保护管理 API 和 WebSocket，与远端 SSH 登录相互独立。

## 运行模式

- 仅绑定 `127.0.0.1`、`::1` 或 `localhost` 时，可以不配置访问凭据，保持本机兼容模式。
- 绑定 `0.0.0.0`、`::` 或其他非 loopback 地址时，必须配置管理密码、Authenticator Secret 或 API Token，否则服务拒绝启动。
- `bin/server.dart` 默认绑定 `127.0.0.1`。

浏览器密码登录：

```powershell
$env:HOSTDECK_ACCESS_PASSWORD = 'replace-with-a-strong-password'
dart run bin/server.dart --host 0.0.0.0 --web-dir host-deck-ui/dist
```

Agent CLI/API Token：

```powershell
$env:HOSTDECK_API_TOKEN = 'replace-with-a-long-random-token'
$env:HOSTDECK_TOKEN = $env:HOSTDECK_API_TOKEN
dart run bin/hostdeck_cli.dart sessions
```

Authenticator/TOTP 登录：

```powershell
$env:HOSTDECK_ACCESS_TOTP_SECRET = 'BASE32-SECRET-FROM-YOUR-AUTHENTICATOR'
dart run bin/server.dart --host 0.0.0.0 --web-dir host-deck-ui/dist
```

Docker 部署需要通过 `-e HOSTDECK_ACCESS_PASSWORD=...` 或 `-e HOSTDECK_API_TOKEN=...` 传入凭据。网络访问还应在 HTTPS 反向代理后提供；认证不能替代 TLS。反向代理通过 HTTP 连接 HostDeck 时，同时设置 `HOSTDECK_SECURE_COOKIES=true`，确保浏览器会话 Cookie 带有 `Secure` 属性。

## 协议

- Web UI 使用 `HttpOnly`、`SameSite=Strict` Cookie，会话默认有效 12 小时。
- Agent CLI 使用 `Authorization: Bearer <token>`，支持 `--token` 和 `HOSTDECK_TOKEN`。
- `/api/status`、`/api/agent/discovery`、`/api/access/state` 和 `/api/access/login` 公开，其余 `/api/*` 与 `/api/ws/*` 均要求认证。
- 浏览器 Cookie 发起的写请求和 WebSocket upgrade 必须具有同源 `Origin`。
- Authenticator 登录使用 RFC 6238 TOTP，默认 6 位、30 秒周期，允许前后一个时间窗口；连续失败会触发登录限流。
- 已登录用户可以在设置页绑定、轮换或停用 Authenticator，绑定后的 Secret 和恢复码哈希保存在数据目录的受保护文件中。

管理密码、API Token 和环境变量 TOTP Secret 从进程环境读取；界面绑定的 TOTP Secret 不写入数据库，而是保存在数据目录的加密文件中。修改环境变量并重启服务会使旧的环境凭据和内存中的浏览器会话失效。
