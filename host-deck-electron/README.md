# HostDeck Electron

`host-deck-electron/` 是 HostDeck 的独立 Electron Windows 壳工程。当前结构中：`src/main/` 承载主进程逻辑，`src/preload/` 提供桥接层，`src/renderer/` 使用 Vue 渲染 Electron 壳界面，并复用根目录 Dart 服务与 `host-deck-ui/` 的前端构建产物。

## 开发命令

安装依赖：

```bash
pnpm install
```

启动 Electron 开发模式：

```bash
pnpm electron:dev
```

构建 Windows 安装包：

```bash
pnpm electron:build:win
```

## 说明

- 开发模式会自动启动 `host-deck-ui` 的 Vite 开发服务器和 `host-deck-electron` 自己的 Vite renderer 开发服务器。
- 如需覆盖开发地址，可分别使用 `HOST_DECK_ELECTRON_APP_DEV_URL` 与 `HOST_DECK_ELECTRON_SHELL_DEV_URL`。
- 预览和打包模式会复用 `host-deck-ui/dist`。
- 打包前会先构建 `bin/server.dart` 的 Windows CLI bundle，再将 `server.exe` 和前端静态资源一起打入安装包。
