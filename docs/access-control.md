# HostDeck 访问认证

HostDeck 的访问认证保护管理 API 和 WebSocket，与远端 SSH 登录相互独立。

## 运行模式

- 仅绑定 `127.0.0.1`、`::1` 或 `localhost` 时，可以不配置访问凭据，保持本机兼容模式。
- 绑定 `0.0.0.0`、`::` 或其他非 loopback 地址时，必须配置管理密码或 API Token，否则服务拒绝启动。
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

Docker 部署需要通过 `-e HOSTDECK_ACCESS_PASSWORD=...` 或 `-e HOSTDECK_API_TOKEN=...` 传入凭据。网络访问还应在 HTTPS 反向代理后提供；认证不能替代 TLS。反向代理通过 HTTP 连接 HostDeck 时，同时设置 `HOSTDECK_SECURE_COOKIES=true`，确保浏览器会话 Cookie 带有 `Secure` 属性。

## 协议

- Web UI 使用 `HttpOnly`、`SameSite=Strict` Cookie，会话默认有效 12 小时。
- Agent CLI 使用 `Authorization: Bearer <token>`，支持 `--token` 和 `HOSTDECK_TOKEN`。
- `/api/status`、`/api/agent/discovery`、`/api/access/state` 和 `/api/access/login` 公开，其余 `/api/*` 与 `/api/ws/*` 均要求认证。
- 浏览器 Cookie 发起的写请求和 WebSocket upgrade 必须具有同源 `Origin`。

管理密码和 API Token 当前从进程环境读取，不会写入数据库。修改环境变量并重启服务会使旧凭据和内存中的浏览器会话失效。
