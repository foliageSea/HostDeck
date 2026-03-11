# 完善文件管理功能计划

本计划旨在完善 SSH 工具的文件管理模块，使其具备现代文件管理器的核心功能，包括批量操作、视图切换、文件编辑等。

## 1. 现状分析
- **已实现功能**：文件列表（仅列表视图）、文件删除、基础文件读写 API（非流式，全量加载到内存）。
- **缺失功能**：批量上传/下载、复制、移动、重命名、新建文件夹、图标视图、文件编辑 UI、加载状态反馈。
- **技术栈**：
    - 前端：Vue 3 + Tailwind CSS + Monaco Editor (已安装)。无 UI 组件库。
    - 后端：Dart (Shelf) + dartssh2。
- **痛点**：当前文件读写为全量加载，无法处理大文件；缺乏基本的文件操作交互。

## 2. 目标功能
1.  **文件操作**：
    - **批量上传**：支持多文件选择，流式上传。
    - **批量下载**：支持多文件打包下载（后端流式生成 .tar.gz）。
    - **复制/移动**：支持文件/文件夹的复制和移动。
    - **重命名**：支持文件/文件夹重命名。
    - **新建文件夹**：支持在当前目录下创建新文件夹。
    - **删除**：支持批量删除。
2.  **视图与交互**：
    - **视图切换**：支持列表模式和图标模式切换。
    - **上下文菜单**：右键菜单支持常用操作（打开、下载、复制、剪切、重命名、删除、属性）。
    - **工具栏**：提供常用操作入口（上传、新建文件夹、刷新、视图切换）。
    - **面包屑导航**：优化路径导航体验。
    - **Loading 状态**：所有异步操作增加 Loading 反馈。
3.  **文件编辑**：
    - 集成 Monaco Editor，支持文本、配置文件、代码的在线编辑和保存。
    - 根据文件扩展名自动识别语言。

## 3. 技术方案

### 3.1 后端 (Dart)
- **依赖调整**：添加 `shelf_multipart` 用于处理文件上传流；添加 `mime` 用于文件类型识别（可选）。
- **SshRepository 增强**：
    - `readFileStream(path)`: 返回 `Stream<List<int>>`，实现流式下载。
    - `writeFileStream(path, stream)`: 接收流并写入文件，实现流式上传。
    - `rename(oldPath, newPath)`: 使用 `sftp.rename` 实现重命名和移动。
    - `createDirectory(path)`: 使用 `sftp.mkdir`。
    - `copy(source, target)`: 执行 `cp -r` 命令（利用服务器能力）。
    - `downloadBatch(paths)`: 执行 `tar -czf - ...paths` 命令，返回 stdout 流（无需服务器产生临时文件）。
- **API 路由扩展**：
    - `GET /api/files/download?path=...`: 流式下载。
    - `POST /api/files/upload`: 处理 `multipart/form-data` 上传。
    - `POST /api/files/batch-download`: 接收路径列表，返回 `application/gzip` 流。
    - `POST /api/files/operate`: 统一处理 `rename`, `move`, `copy`, `mkdir` 等操作。

### 3.2 前端 (Vue)
- **UI 组件 (手写 Tailwind)**：
    - `Modal.vue`: 通用对话框（用于确认、输入名称等）。
    - `Dropdown.vue`: 下拉菜单（用于上下文菜单）。
    - `Toast.vue`: 全局消息提示。
    - `Loading.vue`: 加载动画组件。
- **业务组件**：
    - `FileToolbar.vue`: 工具栏。
    - `FileList.vue`: 列表视图（优化现有表格）。
    - `FileGrid.vue`: 图标视图（新增）。
    - `FileEditor.vue`: 编辑器弹窗，封装 Monaco Editor。
    - `FileUploader.vue`: 上传管理器，显示上传进度。
- **状态管理 (Pinia)**：
    - 更新 `sshStore` 或新建 `fileStore`，管理当前路径、文件列表、视图模式、选中文件、剪贴板（用于复制/粘贴）等状态。

## 4. 实施步骤

### Phase 1: 后端核心改造
1.  **添加依赖**：`shelf_multipart`, `mime`。
2.  **重构 SshRepository**：实现 `readFileStream`, `writeFileStream`，以及 `rename`, `mkdir` 等基础方法。
3.  **实现批量下载与复制**：实现 `downloadBatch` (tar流) 和 `copy` (cp命令)。
4.  **更新 FileController**：实现对应的 API 接口，确保流式响应。

### Phase 2: 前端基础组件与状态
1.  **开发基础 UI 组件**：`Modal`, `Dropdown`, `Toast`, `Loading`。
2.  **完善 Store**：添加文件管理相关状态（viewMode, selectedFiles, clipboard等）。

### Phase 3: 文件列表与视图切换
1.  **开发 FileToolbar**：实现刷新、新建文件夹、视图切换按钮。
2.  **重构 Files.vue**：拆分出 `FileList` 和 `FileGrid` 组件，实现视图切换。
3.  **集成 Loading**：在加载列表时显示 Loading 组件。

### Phase 4: 文件操作交互
1.  **开发 ContextMenu**：实现右键菜单。
2.  **实现操作逻辑**：
    - **重命名/新建文件夹**：使用 Modal 输入名称，调用 API。
    - **复制/移动**：记录路径到剪贴板，在目标目录“粘贴”时调用 API。
    - **删除**：确认对话框，支持批量删除。

### Phase 5: 上传下载与编辑
1.  **开发 FileUploader**：实现文件选择和流式上传逻辑。
2.  **实现下载**：处理单文件流式下载和多文件打包下载。
3.  **集成 Monaco Editor**：实现 `FileEditor` 组件，支持打开文本文件、编辑、保存（调用写入 API）。

## 5. 验证计划
- **功能测试**：
    - 上传/下载大文件（>100MB），验证内存占用和完整性。
    - 批量下载多个文件，验证 tar 包能否解压。
    - 中文文件名测试（重命名、上传、下载）。
    - 列表/图标视图切换流畅性。
    - 文本编辑保存后内容是否正确。
