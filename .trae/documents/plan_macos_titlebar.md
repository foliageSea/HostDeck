# MacOS 风格标题栏改造计划

## 目标
将 `d:\temp_proj\ssh_tool\lib\main.dart` 中的 Windows 风格自定义标题栏重构为 MacOS 风格（居中标题 + 左侧红黄绿交通灯控制按钮）。

## 实施步骤

### 1. 新增 MacOS 风格控制按钮组件
在 `lib/main.dart` 底部（或文件适当位置）新增一个有状态的私有组件 `_MacWindowButtonRow`：
- **功能**：渲染红（关闭）、黄（最小化）、绿（最大化/还原）三个圆形按钮。
- **交互**：实现 `MouseRegion` 悬浮监听，默认仅显示纯色圆形，当鼠标悬浮在按钮组区域时，显示内部对应的黑色半透明小图标（`Icons.close`, `Icons.remove`, `Icons.open_in_full`）。
- **边框细节**：为圆形按钮添加极细的半透明黑色边框，增强立体感和质感。

### 2. 重构标题栏布局 (`_buildTitleBar` 方法)
修改 `_MyAppState._buildTitleBar`，将现有的 `Row` 布局替换为 `Stack` 布局，以便精准控制各元素位置：
- **左侧控制区**：使用 `Positioned(left: 16)` 放置新创建的 `_MacWindowButtonRow` 组件，并绑定 `windowManager` 的 `close()`, `minimize()`, `maximize()/unmaximize()` 方法。
- **居中标题区**：使用 `Align(alignment: Alignment.center)` 放置一个包裹着应用 Icon 和文本 "SSH Tool" 的 `Row`，确保标题在窗口中绝对居中。
- **右侧操作区**：使用 `Positioned(right: 8)` 放置日志切换按钮。将原先基于 `_buildWindowButton` 构建的矩形按钮替换为标准的 `IconButton`（配置合适的 `splashRadius` 和悬浮颜色），保持界面清爽。

### 3. 清理废弃代码
- 删除现有的 `_buildWindowButton` 辅助方法，因为它主要用于构建 Windows 风格的方形悬浮变色按钮，在切换到 MacOS 风格后已不再需要。

### 4. 规范与注释
- 确保所有新增组件和修改后的方法包含完整的函数级别中文注释（如 `/// 构建 MacOS 风格的控制按钮组`）。
- 确保新代码中颜色透明度使用现有的 `withValues(alpha: ...)` 现代语法，与项目中保持一致。

## 预期效果
窗口顶部将呈现类似于原生 MacOS 的沉浸式标题栏：左侧为三个紧凑的红黄绿控制点（带悬浮图标），正中间为应用标题，右侧保留日志面板唤出按钮，整体拖拽窗口的功能 (`DragToMoveArea`) 维持不变。