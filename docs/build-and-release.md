# 构建与发布

本文档记录桌面应用、纯 Dart 服务、Agent CLI 和 Docker 镜像的构建流程。

## 桌面 release

Flutter release 构建使用 `assets/web/` 作为静态前端资源目录。本地构建桌面安装包前，需要先构建前端并同步产物。

基本流程：

```bash
pnpm --dir host-deck-ui build
# 将 host-deck-ui/dist 的内容同步到 assets/web/
flutter build windows --release
```

如果构建 macOS 或 Linux，将 `windows` 替换为对应平台。

## GitHub Actions release

`.github/workflows/release.yml` 会构建 `host-deck-ui/dist`，Windows 桌面 job 会下载前端产物到 `assets/web` 后执行桌面构建。

Electron Windows 打包链路会单独构建 `host-deck-electron/dist`，其中 `src/main/` 是主进程，`src/preload/` 是桥接层，`src/renderer/` 是 Vue 壳界面。

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
pnpm --dir host-deck-ui release 1.0.1
```

版本号可使用 `1.0.1+2` 这类带 build metadata 的格式；文件版本会写入完整版本号，Git tag 会使用去掉 `+...` 后的 `v1.0.1`，以避免 Docker tag 不支持 `+`。

修改发布流程时应同时核对：

- `.github/workflows/release.yml`
- `Dockerfile`
- `pubspec.yaml` 中的 `assets/web/` 声明
- `scripts/build_server.ps1`
- `scripts/build_server.sh`

## 纯 Dart 服务打包

手动构建 CLI bundle：

```bash
pnpm --dir host-deck-ui build
flutter pub get
dart build cli --target bin/server.dart --output build/server
# 将 host-deck-ui/dist 的内容同步到 build/server/bundle/web/
```

构建结果位于 `build/server/bundle/`：

- `build/server/bundle/bin/server(.exe)`：服务可执行文件。
- `build/server/bundle/lib/`：运行时动态库。
- `build/server/bundle/web/`：前端静态资源。

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
docker build -t host-deck:local .
docker run --rm -p 8080:8080 -v host-deck-data:/data host-deck:local
```

容器默认启动参数：

- `--host 0.0.0.0`
- `--port 8080`
- `--web-dir /app/web`
- `--data-dir /data`

## 静态资源关系

- 开发模式：Vite 提供前端资源，后端只提供 API 和 WebSocket。
- 纯 B/S 模式：`bin/server.dart` 通过 `--web-dir host-deck-ui/dist` 提供静态资源。
- 桌面 release：Flutter 打包 `assets/web/`。
- Docker：镜像内 `/app/web` 来自 `host-deck-ui/dist`。

修改任一构建路径时，要同步更新 README、本文档和相关脚本。
