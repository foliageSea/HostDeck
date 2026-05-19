# 设置模块

设置模块负责前端体验配置，包括主题、壁纸和终端相关偏好。

## 代码入口

前端：

- `ssh-tool-ui-next/src/views/Settings/index.vue`
- `ssh-tool-ui-next/src/views/Settings/components/WallpaperSection.vue`
- `ssh-tool-ui-next/src/views/Settings/hooks/useWallpaperSettings.ts`
- `ssh-tool-ui-next/src/stores/settings.ts`
- `ssh-tool-ui-next/src/lib/wallpapers.ts`
- `ssh-tool-ui-next/src/lib/wallpaper-storage.ts`

## 开发要点

- 设置模块主要是前端本地状态，不应依赖 SSH 会话才能打开，除非配置项明确需要远端信息。
- 壁纸相关逻辑应复用 `wallpapers.ts` 和 `wallpaper-storage.ts`。
- 新增设置项时应明确默认值、持久化 key、恢复失败时的 fallback。
- 与终端显示有关的设置要同步终端模块的读取逻辑。
- 使用 Naive UI 组件时保持当前桌面系统视觉风格。

## 持久化要求

- 本地偏好可以使用 localStorage。
- 存储值必须可容错解析，解析失败时回退默认值。
- 不要在设置模块保存 SSH 密码、私钥、token。
