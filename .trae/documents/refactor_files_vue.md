# Files.vue 重构与功能拆分计划

## 1. 重构目标
当前 `src/views/Files.vue` 代码量较多（约 600 行），包含文件列表展示、鼠标拖拽框选、文件系统操作（增删改查）、上传下载逻辑、右键菜单状态以及多个交互弹窗。
本次重构的核心目标是将这些逻辑按功能域（Domain）拆分到独立的 Composables (Hooks) 和组件中，以提升代码的可读性、可维护性和复用性。

## 2. 详细重构步骤

### 步骤一：创建基础目录
创建 `src/composables/file/` 目录，用于统一存放文件管理器相关的 Composition API 逻辑。

### 步骤二：提取文件框选逻辑 (`useFileSelection.ts`)
- **状态迁移**：将 `containerRef`, `isSelecting`, `selectionBox`, `fileRects`, `initialSelection` 移动至此。
- **逻辑迁移**：提取 `handleMouseDown`, `handleMouseMove`, `handleMouseUp` 函数。
- **职责**：专门负责计算鼠标拖拽生成的选取框坐标（x, y, width, height），并判断与 DOM 中 `[data-filename]` 元素的交叉碰撞，进而更新 `fileStore.selectedFiles`。
- **输出**：返回供模板使用的响应式数据和鼠标按下事件处理函数。

### 步骤三：提取文件核心操作逻辑 (`useFileOperations.ts`)
- **状态迁移**：管理弹窗的显示状态 `showMkdirModal`, `showRenameModal`, `showDeleteModal` 以及输入绑定的 `newItemName`。
- **逻辑迁移**：提取 `handleMkdir`, `handleRename`, `handleDelete`, `handlePaste`, `handleDownload`, `uploadFiles`, `handleDrop`, `handleOpen`（及内部调用的 `openEditor`, `openMediaViewer`, `downloadFile`）等方法。
- **职责**：封装与后端 API（`fileApi`）交互的所有核心业务逻辑。
- **输出**：暴露各种文件操作方法，以及弹窗相关的状态变量。

### 步骤四：提取右键菜单逻辑 (`useFileContextMenu.ts`)
- **状态迁移**：提取 `contextMenu` 响应式对象。
- **逻辑迁移**：提取 `handleContextMenu`, `handleContainerContextMenu`, `closeContextMenu`, `handleCopyPath` 方法。
- **职责**：负责管理右键菜单的位置坐标、显隐状态，并根据当前选中的文件状态（单选、多选、未选）动态生成 `contextMenuItems` 列表。由于菜单需要调用文件操作，此 Hook 会接受相关的操作回调（如 `openMkdirModal`, `openRenameModal` 等）作为参数。

### 步骤五：提取弹窗视图组件 (`FileModals.vue`)
- **文件位置**：创建 `src/components/file/FileModals.vue`。
- **职责**：将冗长的 `<Modal>` 模板结构（新建文件夹、重命名、删除确认）封装到独立组件中。
- **交互**：通过 `v-model` 或 Props/Emits 与外部共享 `showMkdirModal`, `showRenameModal`, `showDeleteModal` 和 `newItemName`，并向外 `emit` 确认操作。

### 步骤六：重组并精简 `Files.vue`
- 在 `Files.vue` 中导入并调用上述三个 Hooks：`useFileSelection`, `useFileOperations`, `useFileContextMenu`。
- 引入 `<FileModals />` 替代原有的模板内嵌弹窗。
- 整理 `<template>` 绑定，移除原有的冗余 JS/TS 代码。
- 保证 `Files.vue` 主要作为布局骨架和依赖注入的顶层容器。

## 3. 验收标准
1. **零功能退化**：框选拖拽、右键菜单、所有文件操作均与重构前表现完全一致。
2. **代码减负**：`Files.vue` 的脚本部分代码大幅缩减，组件结构更加清晰。
3. **TypeScript 规范**：拆分后的 hooks 和组件类型定义完善，支持函数级别注释，无明显的类型警告。