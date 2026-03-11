# 前端 UI 优化与服务器列表记忆功能计划

## 1. 概述
本计划旨在优化 `ssh-tool-ui` 的前端样式，使其更加现代、美观（Modern Clean 风格），并增加服务器连接信息的本地记忆功能（不保存密码），提升用户体验。

## 2. 现状分析
- **UI**: 当前 `Home.vue` 仅包含一个简单的连接表单，样式较为基础，缺乏设计感。
- **功能**: 每次连接都需要手动输入所有信息，且没有历史记录或收藏功能。
- **状态管理**: `ssh.ts` 仅管理当前会话状态，未涉及持久化存储。

## 3. 拟定变更

### 3.1 数据结构与状态管理 (src/stores/ssh.ts)
- **新增类型定义**:
  ```typescript
  interface SavedServer {
    id: string;
    name: string; // 显示名称，默认为 user@host
    host: string;
    port: number;
    username: string;
    // 不保存密码
  }
  ```
- **Store 更新**:
  - 新增 `savedServers` 状态，初始化时从 `localStorage` 读取。
  - 新增 Actions:
    - `addServer(server: SavedServer)`: 添加并保存到 localStorage。
    - `removeServer(id: string)`: 删除并更新 localStorage。
    - `updateServer(id: string, server: Partial<SavedServer>)`: 更新信息。

### 3.2 页面布局与样式重构 (src/views/Home.vue)
- **布局调整**:
  - 采用 **双栏布局**（在宽屏下）或 **上下布局**（在移动端）。
  - **左侧/顶部**: “已保存的服务器”列表。
    - 展示服务器名称、地址。
    - 提供“连接”、“编辑”、“删除”操作。
    - 选中某项时，自动填充右侧表单。
  - **右侧/底部**: “新建/编辑连接”表单。
    - 包含：主机、端口、用户名、密码（必填，不保存）、私钥（可选）。
    - 提交按钮：“连接” 和 “保存并连接”。

- **样式优化 (Modern Clean)**:
  - **色彩**: 使用柔和的背景色（如 `bg-gray-50`），卡片使用白色背景加轻微阴影（`shadow-sm` -> `shadow-md`）。
  - **圆角**: 统一使用较大的圆角（`rounded-lg` 或 `rounded-xl`）。
  - **输入框**: 去除默认边框，使用背景色填充（`bg-gray-100`）+ 底部边框动画，或使用清晰的边框加 focus ring。
  - **按钮**: 使用渐变色或纯色加阴影，悬停时有位移或亮度变化。
  - **列表项**: 卡片式设计，悬停高亮。

### 3.3 全局样式微调 (src/App.vue & src/style.css)
- 优化字体设置，确保跨平台显示效果。
- 调整侧边栏（如果存在）的样式，使其与新 Home 页面风格一致。

## 4. 实施步骤

1.  **更新 Store**: 修改 `src/stores/ssh.ts`，添加 `SavedServer` 类型及相关 CRUD 逻辑。
2.  **重构 Home.vue**:
    - 拆分组件（可选，如果代码量大）：`ServerList.vue` 和 `ConnectionForm.vue`。
    - 实现布局和基础样式。
    - 绑定 Store 数据。
3.  **样式美化**: 使用 Tailwind CSS 细化 UI 细节（阴影、过渡、圆角）。
4.  **交互逻辑**:
    - 点击列表项填充表单。
    - 连接成功后询问是否保存（如果是由手动输入触发）。
    - 密码输入框的显隐切换。

## 5. 验证计划
- **功能验证**:
  - 添加服务器：确认列表更新且 localStorage 写入正确。
  - 删除服务器：确认列表移除且 localStorage 更新。
  - 连接流程：点击列表项 -> 填充表单 -> 输入密码 -> 连接成功。
  - 样式检查：在不同分辨率下查看布局响应性。
- **安全性验证**: 确认 `localStorage` 中 **没有** 明文存储密码。

