# @host-deck/webos

Vue 3 桌面交互组件包：窗口生命周期、父子窗口、关闭确认、Dock、启动台、快捷键切换、桌面网格和可注册小组件。**不包含**认证、SSH、终端、文件管理、HostDeck API、Electron 桥接或产品图标。

## 使用

宿主只需提供 Vue `^3.5`；菜单和提示使用包内依赖 Reka UI，不依赖 Naive UI。消费编译后的 ES module、类型声明和 CSS，不需要 UnoCSS、Tailwind CSS、自动导入或路径别名。

```vue
<script setup lang="ts">
import {
  createDesktop,
  createDesktopContext,
  DesktopProvider,
  DesktopShell,
} from '@host-deck/webos'
import '@host-deck/webos/style.css'
import Notes from './Notes.vue'

const context = createDesktopContext(
  createDesktop({
    storageKey: 'my-product:dock:v1',
    defaultDockAppIds: ['notes'],
    apps: [
      { id: 'notes', title: 'Notes', icon: '/notes.svg', component: Notes, showInLaunchpad: true },
    ],
  }),
)
</script>

<template>
  <div style="height: 700px">
    <DesktopProvider :context="context" dispose-on-unmount>
      <DesktopShell>
        <template #brand>My product</template>
        <template #status>Custom status</template>
      </DesktopShell>
    </DesktopProvider>
  </div>
</template>
```

包的 CSS 限定在 `.webos-root` 内，不接管 `body`、字体文件、页面 reset 或全局主题。内部控件跟随 `context.preferences.isDark`，无需额外的 UI Provider。菜单（含子菜单）和提示浮层保持在桌面根节点内。

## API 与扩展

- `createDesktop(options)`：实例独立的响应式运行时，不要求 Pinia。应用注册表保存组件，窗口实例只保存应用 ID 和状态。
- `registerApp(config)`：注册任意非空 ID，重复或保留 ID 会抛错。`singleInstance` 默认 `true`，设为 `false` 允许多实例。
- `openWindow(appId, props?, { parentId?, maximizable?, minimizable?, resizable? })`：返回窗口 ID；单实例已存在时恢复并聚焦。
- `requestCloseWindow(id)`：异步关闭请求，按子窗口优先执行关闭守卫。任一守卫拒绝则整个树保持打开。守卫抛错会向调用者传播，同时释放关闭锁。
- `closeWindow(id)`：跳过确认的强制关闭，仍会执行关闭动画和资源清理。
- `setWindowBeforeClose(id, handler?)`：注册或移除关闭守卫。业务组件通过 `useDesktop()` 和传入的 `windowId` 使用。
- `onWindowClosed(window)`：关闭动画结束后释放宿主资源；`reset()`/`dispose()` 会立即清理现存窗口并取消定时器。每个窗口只清理一次。异步清理错误通过 `onLifecycleError` 报告。
- `canOpen`、`onOpenRejected`、`shouldMaximize`、应用 `defaultProps`：接入业务限制、默认参数及平台策略，不在内核写死业务 ID。
- 应用 `actions`：自定义标题栏按钮，提供 `id`、`label`、`run(window)`。
- `createDesktopPreferences(initial?)`：响应式桌面偏好。由宿主控制或保存；不请求配置 API。
- `createWidgets({ definitions, defaultTypes, storage?, storageKey? })`：宿主注册小组件，也可以用运行时的 `registerWidget(definition)` 追加类型。`DesktopContext.widgets` 提供给 `DesktopWidgets`。
- `DesktopShortcuts`：接收 `{ id, title, icon, x?, y?, open }[]`，通过 `move(id, x, y)` 向宿主报告位置，不解释目录或端口等业务数据。
- `DesktopShell` 的 `topbar`、`brand`、`status`、`desktop` 插槽：提供宿主布局扩展；`desktop` 插槽提供 `showContextMenu(position)`。
- `DesktopShell` 内置 `Ctrl+K` / `Command+K` 快捷搜索：按应用名称或 ID 搜索，方向键选择、Enter 启动、Escape 关闭；已有窗口会恢复并聚焦。只展示 `showInLaunchpad && !hide` 的应用，遵守运行时打开限制。
- `DesktopShell.appSearchShortcut`：可传 `KeyboardShortcut` 自定义搜索快捷键，传 `null` 禁用；默认使用 `createDefaultAppSearchShortcut()`。与窗口切换快捷键冲突时，窗口切换优先。快捷键仅作用于当前激活的桌面，不拦截输入法组合输入或快捷键录制。
- `DesktopAppSearch`：可单独使用的应用搜索组件，接收 `show` 并通过 `close` 事件请求关闭；使用 `DesktopContext` 的应用注册表、主题和浮层容器。
- 快捷搜索支持中文全拼、首字母和跳字母匹配，例如“文件管理”可用 `wenjianguanli`、`wjgl`、`wgl` 搜索；忽略大小写和空白。拼音词库通过 `pinyin-pro` 在首次打开搜索时按需加载，索引随应用注册或重命名更新；词库加载失败时仍可按名称和 ID 搜索。
- `DesktopContext.resolveIcon`：将图标名转换为 URL 或 Vue 组件；不提供时 `icon` 本身作为 URL。`preloadIcons` 可选。
- `wallpaperStyle`、`wallpaperClass`、`wallpaperFilter`、`videoWallpaperUrl`：展示宿主提供的壁纸，上传和 URL 解析属于宿主。

桌面容器需要明确高度。窗口定位基于容器尺寸，桌面激活后才处理窗口快捷键。当前支持浏览器端桌面场景，不承诺 SSR、移动端完整体验或微前端安全隔离。`DesktopProvider.context` 应在挂载期间保持同一个实例；如要替换运行时，请重新挂载 Provider。运行时由宿主负责销毁，或启用 `dispose-on-unmount`。

## 开发与验证

从 `host-deck-ui/` 运行：

```sh
pnpm build:webos
pnpm test:webos
pnpm build:webos-demo
pnpm test:webos-demo
pnpm verify:webos-package
```

最后一条命令将包打为 tarball，并在 workspace 外的新项目中安装、类型检查、构建和测试 demo，检查样式范围及宿主依赖泄漏。临时项目会保留以供检查。

## 许可

GPL-3.0-only，完整许可证随 npm 包提供。HostDeck 的 MacTahoe 图标、品牌和 Maple Mono 字体不包含在此包中；接入方自行提供图标及其他素材。这不是对原项目的重新授权。
