# 全局暗黑模式添加计划

本计划旨在为应用添加全局暗黑模式支持，包括状态管理、自动切换逻辑以及用户界面控制。

## 目标
1.  支持三种主题模式：跟随系统 (Auto)、明亮 (Light)、暗黑 (Dark)。
2.  状态持久化存储，下次访问时自动恢复。
3.  在顶部栏 "外观" 菜单中提供直观的切换选项。
4.  确保全局样式正确响应主题变化。

## 实施步骤

### 1. 状态管理 (`src/stores/settings.ts`)
-   引入 `@vueuse/core` 中的 `usePreferredDark`。
-   添加 `themeMode` 状态，使用 `useStorage` 持久化存储，类型为 `'light' | 'dark' | 'auto'`，默认值为 `'auto'`。
-   实现 `isDark` 计算属性，逻辑如下：
    -   如果 `themeMode` 为 `'auto'`，则返回 `usePreferredDark().value`。
    -   否则返回 `themeMode` 是否为 `'dark'`。
-   添加 `watch` 监听 `isDark` 或 `themeMode` 的变化：
    -   当 `isDark` 为 `true` 时，向 `document.documentElement` 添加 `dark` 类。
    -   否则移除 `dark` 类。
    -   设置 `immediate: true` 以便初始化时立即生效。
-   导出 `themeMode` 和 `setThemeMode` 方法。

### 2. 全局初始化 (`src/App.vue`)
-   在 `App.vue` 中引入并调用 `useSettingsStore`。
-   确保应用启动时立即初始化主题监听逻辑，避免页面闪烁。

### 3. UI 实现 (`src/components/os/TopBar.vue`)
-   引入 `lucide-vue-next` 图标：`Sun`, `Moon`, `Monitor`。
-   引入 `DropdownMenu` 相关子组件：
    -   `DropdownMenuSub`
    -   `DropdownMenuSubTrigger`
    -   `DropdownMenuSubContent`
    -   `DropdownMenuRadioGroup`
    -   `DropdownMenuRadioItem`
    -   `DropdownMenuSeparator`
-   在现有的 "外观" 菜单中添加 "主题模式" 子菜单。
-   使用单选组 (Radio Group) 展示三个选项：
    -   跟随系统 (Monitor Icon)
    -   明亮模式 (Sun Icon)
    -   暗黑模式 (Moon Icon)
-   绑定点击事件以更新 `settingsStore.themeMode`。

## 验证
-   切换到 "暗黑模式"，确认页面背景变黑，文字变白，组件样式正常。
-   切换到 "明亮模式"，确认恢复默认亮色主题。
-   切换到 "跟随系统"，调整操作系统的主题设置，确认网页随之变化。
-   刷新页面，确认主题设置被保留。
