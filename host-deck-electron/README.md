# HostDeck Electron

`host-deck-electron/` 是 HostDeck 的独立 Electron 桌面壳工程，支持 Windows 和 macOS Apple Silicon。当前结构中：`src/main/` 承载主进程逻辑，`src/preload/` 提供桥接层，`src/renderer/` 使用 Vue 渲染 Electron 壳界面，并复用根目录 Dart 服务与 `host-deck-ui/` 的前端构建产物。

## 开发命令

安装依赖：

```bash
pnpm install --frozen-lockfile
```

启动 Electron 开发模式：

```bash
pnpm electron:dev
```

构建 Windows 安装包：

```bash
pnpm electron:build:win
```

构建 macOS Apple Silicon 安装包：

```bash
pnpm electron:build:mac
```

## 说明

- 开发模式会自动启动 `host-deck-ui` 的 Vite 开发服务器和 `host-deck-electron` 自己的 Vite renderer 开发服务器。
- 如需覆盖开发地址，可分别使用 `HOST_DECK_ELECTRON_APP_DEV_URL` 与 `HOST_DECK_ELECTRON_SHELL_DEV_URL`。
- 本地打包命令会先构建 `host-deck-ui/dist`，再将最新前端产物打入安装包；CI 发布流程使用已下载的 `host-deck-ui/dist` artifact。
- 打包前会先构建 `bin/server.dart` 的平台 CLI bundle，再将服务可执行文件和前端静态资源一起打入安装包。
- 打包还需要 Bun 1.4+，用于把 `host-deck-ai` 编译成 `ai/bridge(.exe)` 独立可执行程序。
- Windows 和 macOS 打包图标统一使用 `host-deck-ui/public/favicon.png`，macOS 的应用图标和 DMG 卷图标由打包工具转换生成。
- macOS 包默认使用临时签名（`mac.identity: "-"`），并声明本地网络访问用途。macOS 15 及以上首次连接局域网服务器时，需要允许 HostDeck 访问本地网络；拒绝后可在“系统设置 → 隐私与安全性 → 本地网络”中开启，再重试连接。
- macOS 打包在 `afterPack` 阶段为主程序设置按应用 ID、Electron 版本和架构生成的独立 Mach-O UUID，再进行签名，避免系统将本地网络权限错误归属给使用同版 Electron 的其他应用。当前支持发行使用的 ARM64 单架构包；修改 UUID 后，主程序崩溃日志的符号化需要同步处理对应调试符号的 UUID。
- 开发模式从终端启动时的本地网络权限行为与 Finder 启动应用不同，权限验证需使用打包后的 `.app`。临时签名不能保证跨构建的权限识别稳定性，正式分发建议使用 Developer ID 签名；可通过 `CSC_LINK` / `CSC_KEY_PASSWORD` 配置证书，并覆盖 `mac.identity` 使用正式签名。
