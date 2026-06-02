# 桌面工作台模块

桌面工作台模块提供类似操作系统桌面的前端体验，包括登录屏、桌面、窗口、Dock、顶栏、窗口切换和桌面钉住项。

## 代码入口

前端：

- `host-deck-ui/src/components/os/LoginScreen.vue`
- `host-deck-ui/src/components/os/DesktopShell.vue`
- `host-deck-ui/src/components/os/DesktopWindow.vue`
- `host-deck-ui/src/components/os/DesktopDock.vue`
- `host-deck-ui/src/components/os/DesktopTopBar.vue`
- `host-deck-ui/src/components/os/DesktopWindowSwitcher.vue`
- `host-deck-ui/src/components/os/DesktopPinnedDirectories.vue`
- `host-deck-ui/src/stores/desktop.ts`
- `host-deck-ui/src/stores/window-session.ts`
- `host-deck-ui/src/types/desktop.ts`

## 支持的应用窗口

桌面应用配置集中在 `src/stores/desktop.ts`，当前涉及：

- Dashboard
- Terminal
- Files
- Runtime Sessions
- Docker
- Settings
- Text Editor
- Media Viewer
- Docker create container / compose / services 等子窗口

## 开发要点

- 新增桌面应用时，需要定义 `DesktopAppId`、应用配置、图标、标题和组件。
- 窗口关闭前需要确认的场景，应使用 window before-close handler。
- 会话类窗口当前受 `maxSessionWindows = 8` 限制。
- 桌面钉住目录和端口链接按 SSH 连接维度保存。
- 与具体业务无关的窗口行为应放在 desktop/window-session store，不要放入业务 view。

## 本地存储

`src/stores/desktop.ts` 使用 localStorage 保存部分桌面状态：

- `host-deck:desktop:pinned-directories`
- `host-deck:desktop:pinned-directory-positions`
- `host-deck:desktop:pinned-port-links`
- `host-deck:desktop:pinned-port-link-positions`

修改存储结构时应考虑已有用户数据迁移或容错解析。
