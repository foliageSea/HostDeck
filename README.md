# SSH Tool

`ssh_tool` 是一个跨平台 SSH 工具，当前由三部分组成：

- Flutter 桌面壳：负责窗口承载、日志面板和内置后端服务
- Dart CLI 服务：入口为 `bin/server.dart`，可独立以 B/S 模式运行
- Vue 3 前端：当前主前端位于 `ssh-tool-ui-next/`

当前开发、Docker 构建和发布流程都以 `ssh-tool-ui-next/` 为准；旧 `ssh-tool-ui/` 目录已不存在。

## 功能概览

- SSH 登录与服务器保存
- 桌面式工作台、多窗口、Dock、窗口切换器
- 多会话终端
- 文件管理、收藏目录、桌面钉住目录
- 文本编辑与图片/视频预览
- 系统监控
- 运行态会话查看
- Docker 容器与镜像管理
- 主题、壁纸与终端字体设置

## 技术栈

### 后端 / 桌面壳

- Flutter
- Dart
- shelf / shelf_router / shelf_web_socket
- dartssh2
- sqlite3
- logging

### 前端

- Vue 3
- TypeScript
- Vite
- Naive UI
- UnoCSS
- Pinia
- Vue Router
- TanStack Vue Query
- Axios
- xterm.js
- Monaco Editor
- xgplayer

## 前置要求

- Flutter SDK
- Node.js 20+
- pnpm

先安装依赖：

```bash
flutter pub get
pnpm --dir ssh-tool-ui-next install
```

## 开发模式

### 1. Flutter 桌面壳调试模式

当前 Flutter 桌面调试模式会在 WebView 中加载 Vite 开发服务器，所以需要前端和 Flutter 同时启动。

终端 A：

```bash
pnpm --dir ssh-tool-ui-next dev
```

终端 B：

```bash
flutter run -d windows
```

说明：

- `ssh-tool-ui-next/vite.config.ts` 当前端口是 `http://localhost:5174`
- `lib/main.dart` 的 Flutter debug WebView 仍硬编码加载 `http://localhost:5173`，调试桌面壳前需要先统一端口，或临时让 Vite 使用 5173
- Flutter 内置后端默认监听 `http://localhost:8080`
- `ssh-tool-ui-next/vite.config.ts` 会把 `/api` 和 `/socket.io` 代理到 `http://localhost:8080`

如需在 macOS/Linux 调试桌面壳，把 `windows` 替换为对应设备即可。

### 2. 纯 Dart B/S 模式

先构建前端，再启动 CLI 服务：

```bash
pnpm --dir ssh-tool-ui-next build
dart run bin/server.dart --host 0.0.0.0 --port 8080 --web-dir ssh-tool-ui-next/dist
```

启动后访问 `http://localhost:8080`。

常用参数：

- `--host <value>`：绑定地址，默认 `0.0.0.0`
- `--port <value>`：监听端口，默认 `8080`
- `--web-dir <path>`：静态前端资源目录
- `--data-dir <path>`：sqlite 与配置文件目录

如果未显式传入 `--web-dir`，`bin/server.dart` 会尝试从可执行文件旁的 `../web` 自动发现静态资源目录。

## 桌面发布构建

Flutter release 构建会打包 `assets/web/` 里的静态资源，因此在本地构建桌面安装包前，需要先准备前端产物。

基本流程：

```bash
pnpm --dir ssh-tool-ui-next build
# 将 ssh-tool-ui-next/dist 的内容同步到 assets/web/
flutter build windows --release
```

GitHub Actions 的 `.github/workflows/release.yml` 已经会先构建 `ssh-tool-ui-next/dist`，再把产物放入 `assets/web/` 后执行桌面构建。

## 纯 Dart 服务打包

手动构建 CLI bundle：

```bash
pnpm --dir ssh-tool-ui-next build
flutter pub get
dart build cli --target bin/server.dart -o build/server
# 将 ssh-tool-ui-next/dist 的内容同步到 build/server/bundle/web/
```

构建结果位于 `build/server/bundle/`：

- `build/server/bundle/bin/server(.exe)`：服务可执行文件
- `build/server/bundle/lib/`：运行时动态库
- `build/server/bundle/web/`：前端静态资源

说明：仓库中的 `scripts/build_server.sh` 和 `scripts/build_server.ps1` 目前仍引用已不存在的旧目录 `ssh-tool-ui/`，使用前需要先校正为 `ssh-tool-ui-next/`，否则会失败。

## Docker

`Dockerfile` 当前会直接构建 `ssh-tool-ui-next/` 与 Dart CLI 服务：

```bash
docker build -t ssh-tool:local .
docker run --rm -p 8080:8080 -v ssh-tool-data:/data ssh-tool:local
```

容器默认启动参数：

- `--host 0.0.0.0`
- `--port 8080`
- `--web-dir /app/web`
- `--data-dir /data`

## 常用校验命令

仓库根目录：

```bash
flutter analyze
flutter test
```

前端目录 `ssh-tool-ui-next/`：

```bash
pnpm build
pnpm exec vue-tsc -p tsconfig.app.json --noEmit
pnpm test
```

单个前端测试示例：

```bash
pnpm exec vitest run src/views/Files/components/__tests__/FilePickerDialog.spec.ts
```

## 项目结构

```text
ssh_tool/
├── bin/                 # Dart CLI 服务入口
├── lib/                 # Flutter 桌面壳与内置后端服务
├── ssh-tool-ui-next/    # 当前主前端工程
├── assets/web/          # Flutter release 打包使用的静态资源
├── scripts/             # 服务打包脚本
├── test/                # Flutter/Dart 测试
└── README.md
```

## 开源协议

本项目采用 [MIT License](LICENSE) 开源。
