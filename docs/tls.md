# TLS 访问

HostDeck 的 Electron 内置服务和独立 Dart 服务均支持原生 HTTPS。默认关闭，继续使用原来的监听端口；启用后该端口仅接受 HTTPS，WebSocket 使用 WSS。

## 界面配置

打开“设置 → 安全 → TLS 访问”，开启 TLS，选择证书来源并保存。界面显示当前协议、已保存证书和“待重启生效”状态。保存配置不会断开当前连接。

- **自动生成自签名证书**：使用 RSA 2048 / SHA-256，有效期 365 天。访问地址默认包含 `localhost`、`127.0.0.1`、`::1`；通过局域网访问时，应补充实际 IP，通过域名访问时应补充域名。每行一个地址，也支持空格或逗号分隔。IP 使用 X.509 iPAddress SAN 编码。证书到期前需重新生成并重启。
- **导入 PEM 证书**：同时选择证书链和未加密的 PEM 私钥。证书链的第一张必须是服务端证书，其后放中间证书。保存前校验证书有效期和实际 TLS 握手，失败时保留原配置。

桌面端下次重启应用或内置后端时生效；B/S 部署重启服务进程或容器后生效。重启后把原访问地址的 `http://` 改为 `https://`，端口不变。停用后相应改回 `http://`。服务重启后可能需要重新登录。

自签名证书需在外部浏览器或操作系统中自行信任，可点击“下载证书”获取公开证书。Electron 内置页面和本机 CLI/MCP 会根据本地服务记录校验证书指纹。导入的域名证书用于 Electron 的 loopback 连接时也使用指纹校验；外部浏览器仍按证书中的域名/IP 校验。

配置保存到 `<data-dir>/tls.json`，证书和私钥保存在 `<data-dir>/tls/<版本>/`。运行中的监听继续使用已加载证书，替换证书在重启后生效。POSIX 系统上的证书版本目录权限为 `700`，私钥和配置文件权限为 `600`。Windows 使用数据目录现有访问权限。私钥不会由 API 返回，也不会包含在日志导出中。备份时应保护整个数据目录。

## 无界面启动

首次启动即可生成自签名证书：

```bash
dart run bin/server.dart --tls true --data-dir ./data --web-dir host-deck-ui/dist
```

使用已有证书：

```bash
dart run bin/server.dart --tls true --tls-cert /certs/fullchain.pem --tls-key /certs/privkey.pem --data-dir ./data --web-dir host-deck-ui/dist
```

启动参数优先于环境变量，环境变量优先于保存的配置：

| 参数 | 环境变量 | 用途 |
| --- | --- | --- |
| `--tls true/false` | `HOSTDECK_TLS` | 覆盖持久化的开关 |
| `--tls-cert <path>` | `HOSTDECK_TLS_CERT` | 证书链路径 |
| `--tls-key <path>` | `HOSTDECK_TLS_KEY` | 未加密私钥路径 |

证书路径必须成对提供；提供路径时默认启用 TLS。使用启动参数或环境变量覆盖时，界面显示“启动参数覆盖中”，界面保存的配置在移除覆盖后使用。外部证书文件在每次启动时读取，替换文件后需要重启。

TLS 配置损坏或证书错误会使启动失败。可使用 `--tls false` 强制以 HTTP 启动，然后在界面修复配置；该参数也可覆盖损坏的配置文件。监听非 loopback 地址时仍然需要管理密码、TOTP 或 API Token。

Docker 可挂载 `/data` 持久化界面配置，或将证书目录只读挂载到容器，并传入上述环境变量。无需新增端口映射，也无需容器内安装 OpenSSL。反向代理终止 HTTPS 的部署可继续关闭原生 TLS 并使用 `HOSTDECK_SECURE_COOKIES=true`。

## CLI / MCP

本机通过 discovery 文件自动发现 TLS 服务时，会校验其中的公开证书指纹和证书有效期。连接远端自签名服务时，显式提供受信证书：

```bash
dart run bin/hostdeck_cli.dart sessions --hostdeck-url https://host.example:8080 --ca-cert ./hostdeck-cert.pem
dart run bin/hostdeck_mcp.dart --hostdeck-url https://host.example:8080 --ca-cert ./hostdeck-cert.pem
```

也可设置 `HOSTDECK_CA_CERT`。提供受信证书时仍校验证书有效期和主机名。由系统已信任 CA 签发的证书无需额外配置。

## API

- `GET /api/settings/tls`：返回 `saved`、`active`、`restartRequired`、`managedExternally`。
- `PUT /api/settings/tls`：接收 `enabled`、`source`（`selfSigned` / `imported`），以及可选的 `hosts`、`regenerate`、`certificatePem`、`privateKeyPem`。
- `GET /api/settings/tls/certificate`：下载已保存的公开证书链。

TLS API 复用访问认证和统一 JSON 响应，证书下载成功时直接返回 PEM 文件。

## Vite 开发环境

Vite 的 TLS 与后端 TLS 独立配置。应用前端（默认 5178）和 Electron 开发壳（默认 5180）都支持以下环境变量；证书路径相对于仓库根目录，也可使用绝对路径：

| 环境变量 | 用途 |
| --- | --- |
| `HOSTDECK_DEV_TLS=true` | 开启 Vite HTTPS，默认关闭 |
| `HOSTDECK_DEV_TLS_CERT` | 开发证书链 PEM 路径 |
| `HOSTDECK_DEV_TLS_KEY` | 未加密私钥 PEM 路径 |
| `VITE_DEV_PROXY_TARGET` | 手动启动 Vite 时的后端地址，默认 `http://localhost:8080` |
| `HOSTDECK_DEV_PROXY_CA_CERT` | HTTPS 后端的受信 PEM 证书路径 |

macOS/Linux 示例：

已在默认数据目录生成自签名证书时，可直接运行 `./dev-tls.sh`。脚本自动读取当前证书版本并启用前后端 TLS，也支持传递 `dev.sh` 参数，例如 `./dev-tls.sh --frontend-port 5179`。使用 `./dev-tls.sh --check` 仅校验证书，不启动服务。

```bash
export HOSTDECK_DEV_TLS=true
export HOSTDECK_DEV_TLS_CERT=/absolute/path/cert.pem
export HOSTDECK_DEV_TLS_KEY=/absolute/path/key.pem
./dev.sh
# 或启动 Electron 开发模式（后端另行运行）
pnpm --dir host-deck-electron electron:dev
```

Windows PowerShell：

```powershell
$env:HOSTDECK_DEV_TLS = 'true'
$env:HOSTDECK_DEV_TLS_CERT = 'C:\certs\cert.pem'
$env:HOSTDECK_DEV_TLS_KEY = 'C:\certs\key.pem'
.\dev.ps1
```

可以使用 HostDeck 已生成的证书版本目录中的 `cert.pem` / `key.pem`，或通过本地证书工具生成受信任的开发证书。证书必须包含实际访问域名/IP。浏览器需自行信任自签名证书；Electron 根据开发配置中的证书指纹信任开发页面，其他证书沿用默认校验。Vite 的热更新和终端 WebSocket 自动使用 WSS。

`dev.sh` / `dev.ps1` 会通过临时 ready 文件读取后端实际协议和公开证书。按 `r` 重启后端时，Vite 会重新加载代理配置，适配后端 TLS 开关和证书变化；前端 HTTPS 配置保持原样。后端 TLS 启用后，登录 Cookie 带有 `Secure`，开发前端也应启用 HTTPS，以便在非 localhost 地址正常登录。

手动运行 Vite 或 Electron 开发模式时，如后端使用 HTTPS，需要同时配置代理目标和受信证书：

```bash
export VITE_DEV_PROXY_TARGET=https://127.0.0.1:8080
export HOSTDECK_DEV_PROXY_CA_CERT=/absolute/path/backend-cert.pem
pnpm --dir host-deck-ui dev
```

也可在各自包目录的 `.env.local` 中配置变量；两套 Vite 同时使用时，推荐在启动进程的环境中统一设置。环境变量优先于 env 文件。生产构建不读取开发证书或后端 ready 文件。

开发 TLS 集成验证命令：`pnpm --dir host-deck-ui test:dev-tls`（测试使用本机 OpenSSL 生成临时证书，运行功能不依赖 OpenSSL）。
