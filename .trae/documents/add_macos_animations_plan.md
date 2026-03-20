# 为 OS 组件添加 MacOS 风格交互动画计划

本计划旨在为 `d:\temp_proj\ssh_tool\ssh-tool-ui\src\components\os` 目录下的各个组件添加类似于 MacOS 的丰富交互动画，提升用户体验。我们将主要利用 Vue 的 `<Transition>` / `<TransitionGroup>` 组件、Tailwind CSS 的过渡类以及自定义的 CSS `@keyframes` 来实现这些效果。

## 1. 全局与 Desktop 层动画 (Desktop.vue)
- **窗口打开/关闭动画**：使用 `<TransitionGroup name="window-anim">` 包裹 `Window` 组件的渲染。实现窗口打开时从小放大并淡入（Scale & Fade in），关闭时缩小并淡出。
- **切换器出入场**：为 `WindowSwitcher` 组件包裹 `<Transition name="fade">`，实现切换器调出时的平滑淡入淡出。
- **顶栏和 Dock 入场**：在桌面加载时，让 `TopBar` 从上方滑入，`Dock` 从下方滑入。

## 2. Dock 栏交互增强 (Dock.vue)
- **平滑放大效果 (Magnification)**：增强现有的 hover 效果，使用 `hover:scale-125 hover:-translate-y-2 transition-all duration-300 cubic-bezier(0.4, 0, 0.2, 1)` 让图标在悬浮时放大并轻微上浮，更贴近 Mac 的手感。
- **应用启动跳动 (Bounce)**：添加应用点击后的跳动反馈。点击图标时，给对应的图标添加一个 `animate-bounce` 类的状态，持续短时间，模拟 Mac 打开应用时的图标跳动。
- **指示器动画**：应用下方的小圆点（表示应用已打开）添加缩放淡入的出现动画。

## 3. 窗口操作动画 (Window.vue)
- **最大化/还原平滑过渡**：优化 `Window` 切换到全屏时的过渡。确保 `width`、`height`、`left`、`top` 属性在最大化和还原时有平滑的过渡 (`transition-all duration-300 ease-in-out`)。
- **控制按钮悬浮**：左上角关闭、最小化、最大化按钮的内部图标显示/隐藏使用更平滑的 `transition-opacity duration-200`。

## 4. 窗口切换器 (WindowSwitcher.vue)
- **背景模糊渐变**：切换器出现时，背景的毛玻璃效果 (`backdrop-blur`) 和暗色遮罩平滑过渡。
- **选中项动态放大**：当前选中的窗口图标使用弹簧动画（spring-like transition）放大，并且边框高亮颜色平滑切换。

## 5. 登录界面反馈 (LoginScreen.vue)
- **错误震动反馈 (Shake)**：在密码错误或连接失败时，给登录卡片添加水平震动动画（Shake），模拟 Mac 输错密码时的效果。
- **平滑视图切换**：在“选择服务器”和“新建连接/输入密码”的表单之间切换时，添加平滑的高度和淡入淡出过渡。
- **卡片入场**：现有的 `animate-fade-in` 加上轻微的从下方滑入效果（Slide up）。

## 6. 顶栏动画 (TopBar.vue)
- **入场动画**：添加 `animate-in slide-in-from-top-2 fade-in duration-500 ease-out`。

## 实施步骤
1. **修改 Desktop.vue**：引入 `<TransitionGroup>` 和相关的 CSS 动画类。
2. **修改 Window.vue**：调整动态 `style` 和 `class`，使尺寸和位置变化平滑。
3. **修改 Dock.vue**：加入 bounce 状态逻辑，优化 hover 缩放比例，给选择器弹窗加入 `animate-in`。
4. **修改 WindowSwitcher.vue**：优化整体入场和卡片选中时的平滑过渡。
5. **修改 LoginScreen.vue**：添加 `shake` 动画的 keyframes，并在 `onError` 回调中触发震动状态。
6. **修改 TopBar.vue**：添加初始渲染时的下拉入场动画。

以上修改无需安装新依赖，充分利用项目中现有的 `tailwindcss-animate`、Tailwind 工具类和 Vue 内置动画即可实现极佳的视觉效果。
