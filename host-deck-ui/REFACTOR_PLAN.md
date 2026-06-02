# host-deck-ui 重构计划

## 目标

- 使用 `host-deck-ui` 作为新的前端基座，保留当前产品的桌面式交互模型。
- 以 Naive UI 为主 UI 方案重构 `ssh-tool-ui`，不再延续旧项目对 shadcn/radix 的组件依赖。
- 优先复用稳定的业务逻辑、状态管理和 API 层，逐步替换视图层实现。
- 保证每个阶段结束后都具备可运行、可验证的交付结果，避免大爆炸式迁移。

## 重构范围

旧项目 `ssh-tool-ui` 当前包含以下核心能力：

- 登录与服务器管理
- SSH 会话管理与会话保活
- 桌面壳、Dock、多窗口系统
- 系统监控
- 终端
- 文件管理
- 文本编辑与媒体预览
- Docker 管理

新项目 `host-deck-ui` 当前仅具备：

- Vue 3 + Vite 基础模板
- Naive UI 组件自动导入
- `@vicons/carbon` 图标依赖

因此本次工作本质上是以 `host-deck-ui` 为宿主，重建旧版完整产品能力。

## 设计原则

### 1. 保留桌面式交互

连接前保持登录页体验，连接后进入桌面环境，保留以下核心交互：

- 桌面背景
- 顶部状态栏
- Dock
- 多窗口打开/关闭/最小化/最大化/聚焦
- 窗口切换器

### 2. 业务逻辑优先复用，视图层优先重写

优先复用：

- `src/api/*`
- `src/stores/*`
- `src/composables/*`
- WebSocket 会话与监控逻辑
- 工具函数与类型定义

优先重写：

- 表单
- 弹窗
- 菜单
- 列表与卡片布局
- Toast/通知/确认交互

### 3. 最小可运行增量迁移

每一阶段都必须满足：

- 能运行
- 能验证
- 不依赖后续阶段才能判断成败

### 4. 避免把旧 UI 框架原样搬过来

迁移目标不是复制旧组件树，而是保留产品能力并以 Naive UI 重构表现层。

## 目标目录结构

建议在 `host-deck-ui/src` 下逐步收敛为如下结构：

```text
src/
  api/
  assets/
  components/
    common/
    os/
    file/
    docker/
  composables/
    file/
  lib/
  router/
  stores/
  types/
  utils/
  views/
```

说明：

- `components/os` 负责桌面壳相关组件
- `views` 负责窗口内页面级应用
- `components/common` 放 Naive UI 基础封装与通用部件
- `types` 用于收敛跨模块复用的数据结构

## 模块映射

### 可优先直接迁移的模块

这些模块业务逻辑清晰，UI 依赖较少，适合优先迁移：

- `src/api/auth.ts`
- `src/api/server.ts`
- `src/api/files.ts`
- `src/api/terminal.ts`
- `src/api/system.ts`
- `src/api/docker.ts`
- `src/stores/ssh.ts`
- `src/stores/desktop.ts`
- `src/utils/path.ts`
- `src/utils/image.ts`
- 纯类型定义

### 需要适配后迁移的模块

这些模块可保留主要逻辑，但需要替换部分交互或依赖：

- `src/lib/http.ts`
  - 需要把 toast 与会话失效提示切换到 Naive UI 方案
- `src/stores/settings.ts`
  - 需要检查本地存储与主题实现是否依赖旧 UI 体系
- `src/composables/file/*`
  - 逻辑可复用，但要适配新的菜单、弹窗与上传反馈方式
- `src/composables/useDockerPageState.ts`
  - 逻辑较重，建议后置迁移并做分段验证

### 需要重写的模块

这些模块主要是视图层，建议基于 Naive UI 重新实现：

- `src/App.vue`
- `src/components/os/LoginScreen.vue`
- `src/components/os/Desktop.vue`
- `src/components/os/TopBar.vue`
- `src/components/os/Dock.vue`
- `src/components/os/Window.vue`
- `src/components/os/WindowSwitcher.vue`
- `src/views/Dashboard.vue`
- `src/views/Terminal.vue`
- `src/views/Files.vue`
- `src/views/TextEditor.vue`
- `src/views/MediaViewer.vue`
- `src/views/Docker.vue`
- `src/components/file/*`
- `src/components/docker/*`

## 分阶段计划

## Phase 1: 应用底座

目标：让 `host-deck-ui` 成为可承载桌面式产品的基础工程。

任务：

- 补齐依赖
  - `pinia`
  - `axios`
  - `vue-router`
  - `@tanstack/vue-query`
  - `@vueuse/core`
  - 其余按业务迁移需要补充
- 初始化入口
  - `main.ts` 挂载 Pinia、Router、Naive UI Provider
- 建立全局基础设施
  - `src/lib/http.ts`
  - `src/stores/ssh.ts`
  - `src/stores/desktop.ts`
  - `src/stores/settings.ts`
- 建立图标映射层
  - 将旧版字符串图标统一映射到 `@vicons/carbon`
- 建立全局消息能力
  - 统一使用 Naive UI 的 `message`、`notification`、`dialog`

交付标准：

- 项目可启动
- 全局 Provider 正常工作
- `App.vue` 可以基于连接状态切换登录页和桌面页占位
- HTTP 统一响应与错误处理可用

## Phase 2: 登录与桌面壳

目标：恢复产品主体验，形成第一个可交付版本。

任务：

- 重构登录页
  - 服务器列表
  - 新建连接表单
  - 删除服务器
  - 连接中状态
- 重构桌面壳
  - 桌面背景
  - 顶栏
  - Dock
  - 多窗口容器
  - 窗口切换器
- 打通连接主流程
  - `authApi.connect`
  - `serverApi.list/create/update/delete`
  - `sshStore.setSession/clearSession`
  - 会话监控 WebSocket

交付标准：

- 能进入登录页
- 能加载服务器列表
- 能发起 SSH 连接
- 登录后能进入桌面
- Dock 能打开基础窗口
- 能断开连接并返回登录页

## Phase 3: 监控与终端

目标：优先恢复高频且结构相对独立的能力。

任务：

- 重构监控页
  - CPU
  - RAM
  - Disk
- 重构终端页
  - `xterm` 集成
  - 终端窗口聚焦
  - 终端设置弹窗
  - 复制交互
- 保留原有 WebSocket 通讯逻辑

交付标准：

- 监控页面可打开
- 监控数据可实时刷新
- 终端页面可打开
- 终端收发与 resize 可用

## Phase 4: 文件管理

目标：恢复文件浏览与操作主链路。

任务：

- 迁移文件 API 与文件 store
- 迁移文件主视图与工具栏
- 迁移列表与网格视图
- 迁移右键菜单
- 迁移选择框、批量选择、快捷键
- 迁移上传/下载/新建/删除/重命名流程
- 打通从文件管理打开终端、打开编辑器、打开媒体预览

交付标准：

- 文件列表加载正常
- 可切换列表/网格
- 可执行上传、下载、删除、重命名、新建
- 键盘快捷键与右键菜单基本可用

## Phase 5: 编辑器、媒体预览、Docker

目标：补齐复杂业务模块。

任务：

- 文本编辑器
  - 文件读取
  - 编辑保存
- 媒体预览
  - 图片/视频预览
- Docker 管理
  - 容器列表
  - 镜像列表
  - 日志查看
  - Inspect 详情
  - 启停/重启/删除
  - 批量操作
  - 新建容器与拉取镜像

建议顺序：

1. 文本编辑器
2. 媒体预览
3. Docker

交付标准：

- 编辑器和媒体预览从文件管理可直接打开
- Docker 基础管理能力恢复
- Docker 复杂弹窗和批处理功能可用

## Phase 6: 收尾与统一

目标：完成迁移后的结构收敛与体验统一。

任务：

- 统一主题与视觉风格
- 清理临时兼容代码
- 合并重复类型和工具函数
- 梳理目录与命名规范
- 补充 README 或前端开发说明
- 完成构建与类型检查验证

交付标准：

- 代码结构稳定
- 构建通过
- 类型检查通过
- 主要业务路径可回归验证

## 里程碑

建议以 4 个里程碑跟踪：

### M1

- 登录可用
- 桌面壳可用
- 多窗口可用

### M2

- 监控可用
- 终端可用

### M3

- 文件管理可用
- 编辑器与媒体预览可用

### M4

- Docker 可用
- 视觉与结构统一完成

## 风险与应对

### 1. UI 框架替换成本高

风险：旧项目大量使用 shadcn/radix 组合组件，直接迁移会把旧依赖心智带入新项目。

应对：

- 只复用业务逻辑
- 视图层直接用 Naive UI 重写
- 不再建立一层新的 shadcn 风格封装来模拟旧组件

### 2. 多窗口桌面壳复杂度高

风险：窗口状态、层级、焦点、快捷键互相耦合。

应对：

- 优先稳定 `desktopStore`
- 先完成窗口最小闭环，再叠加动画和细节交互

### 3. 文件管理与 Docker 模块体量大

风险：交互细节多，容易拖慢整体节奏。

应对：

- 文件管理与 Docker 拆开迁移
- 先恢复主流程，再逐步补齐高级操作

### 4. 通知与错误处理分散

风险：旧项目同时存在多个提示体系，迁移后容易混乱。

应对：

- 统一为 Naive UI 的消息与对话框机制
- 通过全局基础设施集中管理

## 验证策略

每阶段至少执行以下验证：

- `pnpm build`
- `pnpm exec vue-tsc -p tsconfig.app.json --noEmit`

联调验证建议覆盖：

- 登录与断开连接
- 会话过期后的自动清理
- 监控 WebSocket
- 终端 WebSocket
- 文件上传/下载
- Docker 基础操作

## 推荐执行顺序

1. 底座与依赖
2. `http`、`sshStore`、`desktopStore`
3. 登录页
4. 桌面壳
5. 监控
6. 终端
7. 文件管理
8. 文本编辑器与媒体预览
9. Docker
10. 收尾与统一

## 第一阶段落地清单

建议先落地以下事项，作为实际开发起点：

1. 安装并整理 `host-deck-ui` 必需依赖
2. 建立 `src/api`、`src/stores`、`src/lib`、`src/components/os`、`src/views` 目录
3. 接入 Pinia、Router、Naive UI Provider
4. 迁移 `http.ts` 并改造消息提示体系
5. 迁移 `sshStore` 与 `desktopStore`
6. 改写 `App.vue`，接入登录态切换
7. 产出登录页和桌面壳占位版本

完成以上内容后，再进入 Phase 2 的完整界面重构。
