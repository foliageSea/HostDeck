# HostDeck 开发文档

本目录记录 HostDeck 各模块的开发约定、代码入口、API 合约和验证方式。项目当前由 Flutter 桌面壳、Dart HTTP/WebSocket 服务、Vue 3 前端三部分组成。

## 推荐阅读顺序

1. `architecture.md`：了解整体架构、启动方式和前后端边界。
2. `backend.md`：了解 Dart 服务端分层、路由和依赖组装。
3. `frontend.md`：了解 Vue 前端目录、状态管理和 HTTP 约定。
4. `api-contract.md`：了解统一响应、错误处理和 WebSocket 约定。
5. `modules/*.md`：按业务模块查看具体开发入口。
6. `development.md`、`build-and-release.md`、`testing.md`：查看本地开发、打包发布和验证命令。

## 文档索引

- `architecture.md`：整体架构
- `backend.md`：后端开发说明
- `frontend.md`：前端开发说明
- `api-contract.md`：API 合约说明
- `development.md`：本地开发流程
- `build-and-release.md`：构建与发布流程
- `testing.md`：测试与校验流程

## 模块文档

- `modules/auth.md`：SSH 连接与认证
- `modules/server-config.md`：服务器配置管理
- `modules/terminal.md`：终端会话
- `modules/files.md`：文件管理
- `modules/system-monitor.md`：系统监控
- `modules/runtime-sessions.md`：运行态会话
- `modules/docker.md`：Docker 管理
- `modules/desktop-shell.md`：桌面工作台与窗口系统
- `modules/settings.md`：设置、主题与壁纸
- `modules/media-editor.md`：文本编辑与媒体预览

## 关键入口

- Flutter 桌面壳入口：`lib/main.dart`
- 纯 Dart B/S 服务入口：`bin/server.dart`
- 服务组装入口：`lib/server/server_service.dart`
- API 路由入口：`lib/server/routes/api_routes.dart`
- 前端入口：`ssh-tool-ui-next/src/main.ts`
- 前端 HTTP 基础设施：`ssh-tool-ui-next/src/lib/http.ts`
- 前端桌面工作台状态：`ssh-tool-ui-next/src/stores/desktop.ts`
