# 构建与发布

本文档记录桌面应用、纯 Dart 服务、Agent CLI 和 Docker 镜像的构建流程。

## 桌面 release

Flutter 桌面 release 已弃用：`pubspec.yaml` 不再声明 `assets/web/`，工作流中的 Flutter 桌面 job 已注释。桌面安装包使用 Electron 构建：

```bash
pnpm --dir host-deck-electron install --frozen-lockfile
pnpm run build:electron:win
# macOS Apple Silicon
pnpm run build:electron:mac
```

构建结果位于 `host-deck-electron/release/`。

## GitHub Actions release

`.github/workflows/release.yml` 会构建 `host-deck-ui/dist` 并作为 artifact 供后续 job 使用，当前启用的发布产物为：Docker 镜像 tar.gz、Windows CLI zip、Electron Windows exe/zip、Electron macOS Apple Silicon dmg/zip。

Electron 打包链路会单独构建 `host-deck-electron/dist`，其中 `src/main/` 是主进程，`src/preload/` 是桥接层，`src/renderer/` 是 Vue 壳界面。

发版脚本会同步 `pubspec.yaml` 与 `host-deck-ui/package.json` 版本号，提交版本变更，打 Git tag，推送到 GitHub，并创建 GitHub Release：

```bash
./scripts/release.sh 1.0.1
```

不传版本号时，脚本会交互式提示输入：

```bash
./scripts/release.sh
```

也可以从前端目录脚本转发执行：

```bash
pnpm run release -- 1.0.1
```

版本号可使用 `1.0.1+2` 这类带 build metadata 的格式；文件版本会写入完整版本号，Git tag 会使用去掉 `+...` 后的 `v1.0.1`，以避免 Docker tag 不支持 `+`。

修改发布流程时应同时核对：

- `.github/workflows/release.yml`
- `Dockerfile`
- `host-deck-electron/` 的构建脚本与 `package.json`
- `scripts/build_server.ps1`
- `scripts/build_server.sh`

## 纯 Dart 服务打包

手动构建 CLI bundle：

```bash
pnpm run build:web
flutter pub get
APP_VERSION="$(sed -n 's/^version:[[:space:]]*//p' pubspec.yaml)"
dart build cli --target bin/server.dart --output build/server
node scripts/build_ai.mjs build/server/bundle
printf '%s' "$APP_VERSION" > build/server/bundle/VERSION
# 将 host-deck-ui/dist 的内容同步到 build/server/bundle/web/
```

构建结果位于 `build/server/bundle/`：

- `build/server/bundle/bin/server(.exe)`：服务可执行文件。
- `build/server/bundle/lib/`：运行时动态库。
- `build/server/bundle/ai/bridge(.exe)`：Bun 编译的 pi-ai 独立可执行程序。
- `build/server/bundle/web/`：前端静态资源。

`scripts/build_ai.mjs` 需要本机安装 Bun 1.4+，并为当前系统和架构编译，不再复制 Node.js 与 `node_modules`。可通过 `HOSTDECK_AI_BUN_TARGET` 指定 Bun 目标平台，例如 `bun-linux-arm64`。

注意：仓库中的 `scripts/build_server.ps1` 和 `scripts/build_server.sh` 当前都以 `host-deck-ui/` 为前端来源。

## Agent CLI 打包

`bin/hostdeck_cli.dart` 只调用已经运行的 HostDeck HTTP API，不包含前端静态资源。可直接使用脚本构建：

```bash
./scripts/build_hostdeck_cli.sh
```

默认构建结果位于 `build/hostdeck-cli/`，可通过 `--output <dir>` 指定输出目录。

## Docker 构建

Dockerfile 当前以 `host-deck-ui/` 为前端来源。

```bash
VERSION="$(sed -n 's/^version:[[:space:]]*//p' pubspec.yaml)"
docker build --build-arg HOSTDECK_VERSION="$VERSION" -t "host-deck:$VERSION" -t host-deck:latest .
docker run --rm -p 8080:8080 -e HOSTDECK_ACCESS_PASSWORD=replace-with-a-strong-password -v host-deck-data:/data "host-deck:$VERSION"
```

`HOSTDECK_VERSION` 会写入镜像的 `org.opencontainers.image.version` 标签，并在容器启动时显示在服务横幅中。Docker 镜像 tag 必须由 `docker build -t` 指定，不能在 Dockerfile 内动态生成。

容器默认启动参数：

- `--host 0.0.0.0`
- `--port 8080`
- `--web-dir /app/web`
- `--data-dir /data`

## 静态资源关系

- 开发模式：Vite 提供前端资源，后端只提供 API 和 WebSocket。
- 纯 B/S 模式：`bin/server.dart` 通过 `--web-dir host-deck-ui/dist` 提供静态资源。
- 桌面 release：Electron 打包（Windows、macOS Apple Silicon）。
- Docker：镜像内 `/app/web` 来自 `host-deck-ui/dist`。

修改任一构建路径时，要同步更新 README、本文档和相关脚本。
