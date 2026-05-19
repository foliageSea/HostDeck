# 系统监控模块

系统监控模块负责采集远端系统状态、维护监控历史，并通过 HTTP 和 WebSocket 提供给前端仪表盘。

## 代码入口

后端：

- `lib/server/controllers/system_controller.dart`
- `lib/server/controllers/system/system_monitor_ws_handler.dart`
- `lib/server/controllers/system/session_status_ws_handler.dart`
- `lib/server/services/monitor_service.dart`
- `lib/server/services/monitor_history_service.dart`
- `lib/server/services/ssh_service.dart`
- `lib/server/repositories/ssh_repository.dart`
- `lib/server/models/system_status.dart`

前端：

- `ssh-tool-ui-next/src/api/system.ts`
- `ssh-tool-ui-next/src/views/Dashboard/index.vue`

## API 与通道

- `GET /api/status`：获取当前系统状态。
- `GET /api/system/monitor/history`：获取系统监控历史。
- `GET /api/ws/monitor`：系统监控 WebSocket 推送。
- `GET /api/ws/session`：SSH 会话状态 WebSocket 推送。

## 开发要点

- `MonitorService` 负责从远端系统采集状态并解析命令输出。
- `MonitorHistoryService` 负责历史数据缓存和查询。
- WebSocket handler 应控制推送频率，避免前端和 SSH 连接压力过大。
- 前端仪表盘应能处理字段缺失、采集失败和连接断开的状态。
- 新增监控字段时需要同步 `system_status.dart`、解析逻辑、前端 API 类型和 Dashboard 展示。

## 相关测试

- `test/monitor_service_test.dart`
- `test/monitor_history_service_test.dart`
