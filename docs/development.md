# 本地开发流程

本文档记录本项目本地开发的推荐流程。

## 前置要求

- [独立 Dart SDK](https://dart.dev/get-dart) 3.11.0+（将 `dart` 加入 `PATH`，用 `dart --version` 确认版本）
- Node.js 22.19+（低于 23）
- pnpm 10.34.5（仓库根目录 `package.json` 已固定版本）
- Bun 1.4+（构建 pi-ai 独立可执行程序）

在仓库根目录安装依赖：

```bash
git submodule update --init --recursive
dart pub get
pnpm run install:all
```

## 一键启动后端与前端

macOS / Linux：

```bash
./dev.sh
```

Windows PowerShell：

```powershell
.\dev.ps1
```

脚本使用 `PATH` 中的 `dart` 启动后端，等待服务就绪后再启动 Vite。默认后端地址为 `http://127.0.0.1:8080`，浏览器访问 `http://localhost:5178`。

[dev.sh](../dev.sh) 默认把仓库根目录下的 `build/sidecar-assets` 作为文件 SideCar 资产目录，只加载已有产物，不在启动时编译。可通过 `HOSTDECK_FILE_SIDECAR_DIR` 覆盖（相对路径仍以仓库根目录为基准），或用 `HOSTDECK_FILE_SIDECAR=off` 禁用。缺少资产时，文件任务沿用兼容模式。生成方法见[文件 SideCar 资产](build-and-release.md#文件-sidecar-资产)。

使用 `dev.sh` 调试 Authenticator/TOTP 登录时，可以传入已有的 Base32 Secret：

```bash
./dev.sh --totp-secret 'BASE32_SECRET'
```

也可以使用固定的开发 Secret，方便在 Authenticator 应用中重复配置：

```bash
./dev.sh --enable-totp
```

脚本会在启动时打印该开发 Secret。它只适用于本地调试，不要用于生产环境。也可以直接通过 `HOSTDECK_ACCESS_TOTP_SECRET` 环境变量配置 Secret。

## Electron 桌面开发

运行以下命令启动两个 Vite 开发服务和 Electron。Electron 主进程会启动自己的 Dart 后端，默认使用端口 18080，被占用时会选用空闲端口：

```bash
pnpm --dir host-deck-electron electron:dev
```

两个开发服务器的地址分别来自 `host-deck-ui/vite.config.ts` 与 `host-deck-electron/vite.config.mjs`，也可通过 `HOST_DECK_ELECTRON_APP_DEV_URL` 与 `HOST_DECK_ELECTRON_SHELL_DEV_URL` 覆盖。

## 纯 Dart B/S 模式

先构建前端，再启动含静态资源的服务：

```bash
pnpm run build:web
dart run bin/server.dart --web-dir host-deck-ui/dist
```

启动后访问 `http://localhost:8080`。

非 loopback 监听必须通过 `HOSTDECK_ACCESS_PASSWORD`、`HOSTDECK_ACCESS_TOTP_SECRET` 或 `HOSTDECK_API_TOKEN` 启用访问认证。仅本机开发可省略 `--host`，默认绑定 `127.0.0.1`。完整说明见 `docs/access-control.md`。

常用参数：

- `--host <value>`：绑定地址，默认 `127.0.0.1`。
- `--port <value>`：监听端口，默认 `8080`。
- `--web-dir <path>`：静态前端资源目录。
- `--data-dir <path>`：sqlite 与配置文件目录。
- `--log-dir <path>`：日志文件目录，默认是数据目录下的 `logs`。
- `--log-max-days <days>`：日志最大保留天数，默认 `30`。
- `--enable-secure-browser`：允许服务进程启动使用 SSH SOCKS5 代理的 Chrome。
- `--chrome-path <path>`：覆盖自动探测的 Chrome 可执行文件路径。

纯 B/S 服务按本地日期生成 `hostdeck-server-YYYY-MM-DD.log`，并在启动和日期切换时清理超过保留天数的日志。

## 前端独立开发

启动 Vite：

```bash
pnpm --dir host-deck-ui dev
```

Vite 开发服务器端口以 `host-deck-ui/vite.config.ts` 的 `server.port` 为准。Vite 会将 `/api` 代理到 `VITE_DEV_PROXY_TARGET`，默认是 `http://localhost:8080`；终端 WebSocket 使用 `/api/ws/terminal`。前端独立开发时，需要确保后端服务已经启动。

## 新功能开发流程

涉及后端 API 的功能通常按以下顺序开发：

1. 在 `lib/server/features/<feature>/` 定义或调整模型、controller 与 service。
2. 在 `lib/server/core/ssh/` 或 feature 内 repository 封装外部访问。
3. 在 `lib/server/app/` 的依赖组装中接入新 feature。
4. 在 `lib/server/routes/` 实现并注册路由。
5. 在 `lib/server/routes/api_routes.dart` 注册路由。
6. 在 `host-deck-ui/src/api/` 添加前端请求和类型。
7. 在 `src/stores/`、`src/views/` 或 `src/components/` 中接入 UI。
8. 补充或更新测试。
9. 更新 `docs/` 中对应模块文档。

只涉及前端 UI 的功能通常按以下顺序开发：

1. 确认是否是桌面应用窗口、普通组件还是业务视图。
2. 如需新窗口，先更新 `src/types/desktop.ts` 和 `src/stores/desktop.ts`。
3. 实现 view、component 或 hook。
4. 使用 `src/lib/http.ts`、`src/lib/ui.ts`、Pinia store 等现有基础设施。
5. 运行前端构建、类型检查或相关测试。

## 代码风格

- 后端日志使用 `package:logging/logging.dart`。
- 前端跨目录引用优先使用 `@/xxx`。
- 前端不要保留未使用导入、变量和参数。
- 不要记录或持久化密码、私钥、token。
- 优先做小而明确的改动，避免无必要重构。
