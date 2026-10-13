# HostDeck UI

`host-deck-ui` 是 `host_deck` 的当前前端目录，基于 Vue 3、TypeScript、Vite 与 Naive UI，提供桌面式远程主机工作台体验。

当前项目已经完成主要业务迁移，包含以下能力：

- 登录与服务器管理
- 桌面壳、多窗口、Dock、窗口切换器
- 系统监控
- 终端
- 文件管理
- 文本编辑与媒体预览
- Docker 管理
- 设置与主题切换

## 技术栈

- Vue 3
- TypeScript
- Vite
- Naive UI
- Pinia
- Vue Router
- TanStack Vue Query
- Axios
- Xterm.js

## 目录说明

桌面内核已抽离为 workspace package，HostDeck 仅负责业务组装：

- `packages/webos/`：通用 Vue 桌面运行时和组件，详见其 `README.md`。
- `examples/webos-demo/`：独立宿主，只消费 package 的构建产物。
- `src/lib/host-desktop-apps.ts`：HostDeck 应用注册和默认参数。
- `src/stores/desktop.ts`：兼容原入口，保留 SSH 资源清理、Electron 策略和远程快捷方式。
- `src/stores/desktop-preferences.ts`：本地桌面偏好；业务设置和壁纸 API 仍在 `settings.ts`。

```text
src/
  api/              API 请求封装
  components/
    common/         通用基础组件
    os/             桌面壳、Dock、窗口系统、登录页
  lib/              HTTP 与全局 UI 基础设施
  router/           路由配置
  stores/           Pinia 状态管理
  types/            跨模块类型定义
  utils/            工具函数
  views/            各业务窗口页面
```

## 开发命令

安装依赖：

```bash
git submodule update --init --recursive
pnpm install
```

启动开发环境：

```bash
pnpm dev
```

构建：

```bash
pnpm build
```

类型检查：

```bash
pnpm exec vue-tsc -p tsconfig.app.json --noEmit
```

## 联调说明

- Vite 开发代理默认转发到 `http://localhost:8080`
- 可通过 `.env` 中的 `VITE_DEV_PROXY_TARGET` 覆盖，例如：`VITE_DEV_PROXY_TARGET=http://127.0.0.1:9000`
- Electron 壳未最大化时，UI 内部窗口默认不自动最大化；如需开启，可在构建前设置 `VITE_ELECTRON_MAXIMIZE_UI_WHEN_WINDOWED=true`。
- WebSocket 也通过 `/api` 代理到同一后端
- 启动联调前请先确认 Flutter 侧内置服务监听端口与这里一致

## 约定

- 优先复用 `src/api`、`src/stores`、`src/composables` 一类业务逻辑
- 业务视图使用 Naive UI；独立 `@host-deck/webos` 桌面组件包使用 Reka UI + UnoCSS，不要求宿主提供 Naive UI
- 普通 JSON API 默认经过 `src/lib/http.ts` 的统一解包与错误处理
- 全局消息、通知、确认框统一经由 `src/lib/ui.ts`

## 验证

提交前至少执行：

```bash
pnpm build
pnpm exec vue-tsc -p tsconfig.app.json --noEmit
pnpm test
pnpm test:webos
pnpm build:webos-demo
pnpm test:webos-demo
pnpm verify:webos-package
```

`pnpm dev`、`pnpm build`、`pnpm test` 会先构建桌面 package。直接调用 `vite`、`vue-tsc` 或 `vitest` 前需先执行 `pnpm build:webos`。开发 package 后需要重新构建它；`pnpm dev:webos-demo` 可启动独立示例（端口 5180）。
