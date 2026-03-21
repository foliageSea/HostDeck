# 使用 vue-sonner 替换 views 目录中的消息提示计划

## 目标

将 `d:\temp_proj\ssh_tool\ssh-tool-ui\src\views\` 目录下的各个组件中使用的消息提示（包括 `useToastStore` 封装的提示和原生的 `alert`）替换为 `vue-sonner` 库，以统一提示风格并提升用户体验。

## 实施步骤

### 1. 全局配置 `vue-sonner`

*由于* *`vue-sonner`* *需要在其 Toaster 挂载后才能显示提示，首先需要在根组件中配置它。同时兼容保留项目中原有的 shadcn* *`Toaster`* *以免破坏其他未修改模块。*

* **文件**: `d:\temp_proj\ssh_tool\ssh-tool-ui\src\App.vue`

* **操作**:

  * 在 `<script setup>` 中引入 `vue-sonner` 的 `Toaster`，为了避免命名冲突重命名为 `SonnerToaster`：
    `import { Toaster as SonnerToaster } from 'vue-sonner';`

  * 在 `<template>` 中添加 `<SonnerToaster position="top-right" richColors />` 标签（紧跟在原 `<Toaster />` 下方）。

### 2. 重构 `src/views/Terminal.vue`

* **文件**: `d:\temp_proj\ssh_tool\ssh-tool-ui\src\views\Terminal.vue`

* **操作**:

  * 移除 `import { useToastStore } from '../stores/toast'`。

  * 移除实例化语句 `const toast = useToastStore()`。

  * 引入 `import { toast } from 'vue-sonner'`。

  * 文件内的 `toast.success` 和 `toast.error` API 与 `vue-sonner` 完全兼容，无需修改调用方式。

### 3. 重构 `src/views/Files.vue`

* **文件**: `d:\temp_proj\ssh_tool\ssh-tool-ui\src\views\Files.vue`

* **操作**:

  * 移除 `import { useToastStore } from '../stores/toast'`。

  * 移除实例化语句 `const toast = useToastStore()`。

  * 引入 `import { toast } from 'vue-sonner'`。

  * 确保所有的 `toast.success`, `toast.error`, `toast.info` 保持不变，即可正常工作。

### 4. 重构 `src/views/TextEditor.vue`

* **文件**: `d:\temp_proj\ssh_tool\ssh-tool-ui\src\views\TextEditor.vue`

* **操作**:

  * 移除 `import { useToastStore } from '@/stores/toast'`。

  * 移除实例化语句 `const toast = useToastStore()`。

  * 引入 `import { toast } from 'vue-sonner'`。

  * 保持 `toast.success` 和 `toast.error` 的调用方式不变。

### 5. 重构 `src/views/Home.vue`

* **文件**: `d:\temp_proj\ssh_tool\ssh-tool-ui\src\views\Home.vue`

* **操作**:

  * 引入 `import { toast } from 'vue-sonner'`。

  * 将原生的 `alert('Host and Username are required to save.')` 替换为 `toast.warning('Host and Username are required to save.')`。

  * 将原生的 `alert('Connection failed: ' + (error.response?.data || error.message))` 替换为 `toast.error('Connection failed: ' + (error.response?.data || error.message))`。

## 验证与测试

* 确保应用能够正常编译且不报错。

* 分别进入这 4 个视图，触发对应的成功或失败事件，验证是否能正确弹出 `vue-sonner` 样式的消息提示。

