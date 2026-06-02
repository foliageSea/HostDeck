# 前端开发说明

当前主前端位于 `host-deck-ui/`。前端使用 Vue 3、TypeScript、Vite、Naive UI、UnoCSS、Pinia、Vue Router、TanStack Vue Query、Axios、xterm.js、Monaco Editor 和 xgplayer。

## 目录职责

- `src/main.ts`：前端入口。
- `src/App.vue`：应用根组件。
- `src/router/index.ts`：Vue Router 路由与登录守卫。
- `src/api/`：后端 API 类型与请求封装。
- `src/lib/http.ts`：Axios 实例、统一响应解包、会话错误处理。
- `src/lib/ui.ts`：全局消息、通知、确认框桥接。
- `src/stores/`：Pinia 状态。
- `src/components/os/`：桌面壳 UI、窗口、Dock、顶栏。
- `src/components/common/`：通用组件。
- `src/components/editor/`：编辑器组件。
- `src/views/`：业务窗口和页面。
- `src/utils/`：纯工具函数。

## 路由与桌面窗口

`src/router/index.ts` 当前注册传统页面路由：

- `/dashboard`
- `/terminal`
- `/files`
- `/runtime-sessions`

这些路由都带 `requiresAuth`，未连接 SSH 时路由守卫返回 `false`。

桌面工作台主要由 `src/stores/desktop.ts` 和 `src/components/os/*` 驱动。新增桌面应用窗口时，优先在 desktop store 中登记应用配置，再实现对应 view 组件。

## HTTP 请求约定

所有普通 API 请求应复用 `src/lib/http.ts` 的 `http` 实例。该实例会：

- 使用 `/` 作为 `baseURL`。
- 将统一响应中 `code === 200` 的 `data` 解包到 `response.data`。
- 将 `code !== 200` 转换为 `AxiosError`。
- 检测部分 SSH 会话失效错误，并清理前端 SSH 会话。

不要在业务组件中绕过该实例直接创建新的 Axios 客户端，除非接口不符合统一响应模型并且有明确理由。

## UI 通道

全局消息、通知、确认框应走 `src/lib/ui.ts`。工具函数和 store 不应直接创建新的 UI 实例，避免多套消息通道并存。

## TypeScript 约束

`tsconfig.app.json` 开启了严格的无用代码检查，包括：

- `noUnusedLocals`
- `noUnusedParameters`
- `erasableSyntaxOnly`
- `noFallthroughCasesInSwitch`

新增代码时要及时删除未使用导入、变量和参数。路径别名是 `@/* -> src/*`，跨前端目录引用优先使用 `@/xxx`。

## 样式与组件

- UI 基于 Naive UI + UnoCSS。
- 自动导入会生成 `auto-imports.d.ts` 和 `components.d.ts`。
- 在现有视图内开发时应延续当前设计语言，不要引入与现有桌面壳不一致的大量视觉规则。
