# 计划：将 SSH 工具前端重构为 MacOS 风格的 Web 桌面

## 摘要
将现有的 Vue 3 前端转换为类似 MacOS 的桌面环境。应用程序将包含用于 SSH 登录的锁屏界面、带有 Dock 栏、顶部菜单栏和窗口管理器的桌面环境。现有的功能（终端、文件管理器、监控仪表盘）将被重构为在可拖动、可调整大小的窗口中运行的“应用程序”。

## 目标
- **沉浸式体验**：模仿 MacOS 桌面外观和感觉（任务栏、Dock、窗口控件）。
- **窗口管理**：支持多窗口打开、拖拽、调整大小、最小化、最大化以及层级管理（z-index）。
- **无缝集成**：在新的窗口化界面中复用现有的 SSH、终端和文件管理逻辑。

## 当前状态分析
- **框架**：Vue 3 + Vite + Pinia + Tailwind CSS。
- **路由**：使用 `vue-router` 进行全页导航（`/`，`/dashboard`，`/terminal`，`/files`）。
- **布局**：侧边栏 + 内容区域（`App.vue`）。
- **状态**：`sshStore` 管理连接状态。

## 拟定架构

### 1. 目录结构
创建一个新的 `src/components/os` 目录用于存放桌面组件：
- `src/components/os/Desktop.vue`：主桌面容器。
- `src/components/os/Dock.vue`：底部应用程序 Dock 栏。
- `src/components/os/TopBar.vue`：顶部系统状态栏。
- `src/components/os/Window.vue`：通用窗口容器，带控制按钮。
- `src/components/os/LoginScreen.vue`：重构后的登录界面。
- `src/stores/desktop.ts`：窗口和桌面的状态管理。

### 2. 状态管理 (`src/stores/desktop.ts`)
- **状态**：
  - `windows`：打开的窗口对象数组 `{ id, title, component, icon, x, y, width, height, isMinimized, isMaximized, zIndex }`。
  - `activeWindowId`：当前聚焦窗口的 ID。
  - `zIndexes`：管理窗口堆叠顺序。
- **动作**：
  - `openWindow(appId)`：打开或聚焦一个应用程序。
  - `closeWindow(id)`：移除窗口。
  - `minimizeWindow(id)`：隐藏窗口。
  - `maximizeWindow(id)`：切换全屏。
  - `focusWindow(id)`：将窗口置于最前。

### 3. 组件重构

#### `App.vue`
- 替换基于 `router-view` 的布局为条件渲染：
  - 如果 `!sshStore.isConnected`：渲染 `LoginScreen`。
  - 如果 `sshStore.isConnected`：渲染 `Desktop`。
- 移除全局侧边栏。

#### `LoginScreen.vue` (新)
- 替换 `Home.vue` 的功能。
- 视觉效果：模糊背景，用户头像（通用），密码输入框（SSH 密码），“连接”按钮。
- 逻辑：复用 `sshStore.connect` 逻辑。

#### `Desktop.vue` (新)
- 布局：
  - `TopBar`（顶部固定）。
  - `WindowArea`（中间相对定位）。
  - `Dock`（底部固定）。
- 使用 `Window` 组件通过 `v-for="window in windows"` 渲染窗口。

#### `Window.vue` (新)
- Props：`window` 对象。
- 功能：
  - **可拖拽**：标题栏作为拖拽手柄。
  - **可调整大小**：边缘/角落的处理手柄。
  - **控件**：Mac 风格的红绿灯按钮（关闭/最小化/最大化）。

#### `Dock.vue` (新)
- 应用程序列表：终端、文件管理、监控（Dashboard）、设置（登出/断开连接）。
- 悬停效果（简单的缩放效果）。
- 打开应用程序的指示器。

#### 现有视图 (`Terminal.vue`, `Files.vue`, `Dashboard.vue`)
- 从“视图”转换为“组件”。
- 确保它们填充父容器（100% 宽度/高度）以适应窗口内部。
- 移除任何可能与窗口框架冲突的视图特定布局内边距。

## 实施步骤

### 阶段 1：基础与 Store
1. 创建 `src/stores/desktop.ts` 管理窗口状态。
2. 创建基本的 `Desktop.vue`、`TopBar.vue` 和 `Dock.vue` 框架。

### 阶段 2：窗口系统
1. 实现带有拖拽和调整大小逻辑的 `Window.vue`（使用原生 DOM 事件）。
2. 将 `Window.vue` 集成到 `Desktop.vue` 中。
3. 测试打开/关闭虚拟窗口。

### 阶段 3：登录与集成
1. 使用 `Home.vue` 的逻辑但采用新的 UI 创建 `LoginScreen.vue`。
2. 更新 `App.vue` 以在登录和桌面之间切换。

### 阶段 4：应用迁移
1. 将 `Terminal.vue`、`Files.vue`、`Dashboard.vue` 的逻辑封装进桌面窗口系统。
2. 在 `desktop.ts` 中添加“应用程序”配置（映射 App ID 到组件）。
3. 在 Dock 或 TopBar 中实现“断开连接”以返回登录界面。

### 阶段 5：润色
1. 应用类似 MacOS 的样式（Tailwind）。
2. 添加壁纸和图标。
3. 确保响应式（在小屏幕上隐藏 Dock 或调整布局）。

## 验证计划
- **登录**：验证 SSH 连接是否正常工作并过渡到桌面。
- **窗口管理**：
  - 打开终端 -> 验证 xterm 是否正常工作。
  - 打开文件 -> 验证文件导航是否正常工作。
  - 拖动窗口 -> 验证位置更新。
  - 调整窗口大小 -> 验证内容调整。
  - 最小化/最大化 -> 验证状态更改。
- **多任务处理**：打开多个窗口，检查 z-index 聚焦是否正确。

