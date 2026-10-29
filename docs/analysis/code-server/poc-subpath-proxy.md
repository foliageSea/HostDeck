# PoC：code-server 走 HostDeck 同源子路径反代（实测记录）

> 执行人：lead｜时间：2026-10-29｜环境：Linux x64、Dart 3.11.0、code-server v4.143.1 standalone
> 目的：验证「同源 `/ide/` 反向代理 + iframe 内嵌」在技术上是否成立，以及前缀如何映射。
> 结论用于 `code-server-feasibility.md`，不是产品实现代码。

## 1. 实测对象

- 下载 `code-server-4.143.1-linux-amd64.tar.gz`（219MB，GitHub Release），解压后 **676MB**。
- 启动命令（全部仅 loopback）：

```bash
./bin/code-server --auth none --bind-addr 127.0.0.1:19080 \
  --disable-telemetry --disable-update-check \
  --user-data-dir /tmp/cs-data --extensions-dir /tmp/cs-ext \
  --disable-workspace-trust
```

- 代理：临时 Dart shelf 脚本（`/tmp/ide_proxy_poc.dart`），`/ide/*` 分流，HTTP 用 `HttpClient(autoUncompress=false)`，WS 用 `request.hijack` 后原始 socket 双向桥接，并重写 `Host/Origin` 到上游。
- 上游健康：`GET /healthz` → `{"status":"alive",...}`。

## 2. 结果（关键证据）

| 测试 | 结果 | 说明 |
| --- | --- | --- |
| 代理 **剥离前缀**（`/ide/X` → `/X`）访问 `/ide/` | **200** | 返回 workbench HTML |
| 同上，取深度静态资源 `/ide/stable-<hash>/static/out/.../workbench.js` | **200，5,397,239 bytes** | 资源路径可穿透 |
| 同上，`workbench.css` / `manifest.json` | **200 / 200** | |
| 同上，`/ide/healthz` | **200** JSON | 健康检查可代理 |
| 同上，不存在的路径 `/ide/nope-nope` | **404** | 上游 404 正确透传 |
| 同上，WebSocket `ws://.../ide/healthz` | **连接成功** | hijack + 原始字节桥接可用 |
| 代理 **保留前缀**（`/ide/X` → `/ide/X`）访问 `/ide/` 与其静态资源 | **404 / 404** | Express 路由挂在根，前缀保留会全部 404 |

## 3. 结论

1. **必须剥离 `/ide` 前缀再发给 code-server**；code-server 依赖相对 URL（`serverBasePath: "."`、`./_static`、相对 callback/serviceWorker）让浏览器把请求再带回 `/ide/`。这与其 `patches/base-path.diff`「path-rewriting reverse proxy」的定位一致。
2. **同源 iframe 可行**：code-server 返回 `X-Frame-Options: SAMEORIGIN` 和 CSP（`connect-src 'self' ws: wss:`）。由于 iframe 文档与宿主同为 `https://host/ide/`，SAMEORIGIN/同源 CSP 均放行；**若 iframe 直连 `127.0.0.1:<port>`（异源）会被 XFO 拦截**，这是「必须反代、不能直连端口」的硬证据。
3. **gzip 必须原样透传**：代理需 `autoUncompress=false` 并保留 `content-encoding`，否则响应头与 body 不一致。
4. **WS 可代理**：shelf `request.hijack` 拿到原始 socket，重放握手头（含 `Sec-WebSocket-Key`）后双向 pipe 即可；PoC 中 `/ide/healthz` 升级成功。code-server 对 WS 做 Origin/Host 一致性校验，代理需把 `Origin` 重写为上游地址，或给 code-server 配 `--trusted-origins`。
5. **404 不能被 SPA fallback 吞掉**：反代必须挂在 Pipeline 分流层，而不是 `Cascade` 尾部（见 backend.md §1.2）。

## 4. 未覆盖 / 待实测

- 完整 VS Code workbench（真实浏览器）加载：扩展 host、终端、文件树、webview、Service Worker scope（`Service-Worker-Allowed: /`）尚未用浏览器验证。
- 多实例同源（多个 code-server 会话）时 IndexedDB/localStorage 的隔离性。
- HTTPS 反向代理 + Secure Cookie + iframe 的完整链路。
- Windows standalone / macOS arm64 实机启动。
