# 服务器配置模块

服务器配置模块负责保存、读取、更新和删除常用 SSH 服务器配置。

## 代码入口

后端：

- `lib/server/controllers/server_controller.dart`
- `lib/server/repositories/server_repository.dart`
- `lib/server/services/database_service.dart`
- `lib/server/models/server_config.dart`

前端：

- `ssh-tool-ui-next/src/api/server.ts`
- `ssh-tool-ui-next/src/components/os/LoginScreen.vue`

## API

- `GET /api/servers`：获取服务器配置列表。
- `POST /api/servers`：创建服务器配置。
- `PUT /api/servers/<id>`：更新服务器配置。
- `DELETE /api/servers/<id>`：删除服务器配置。

## 数据流

1. 前端通过 `src/api/server.ts` 发起请求。
2. `ServerController` 解析请求并调用 `ServerRepository`。
3. `ServerRepository` 基于 `DatabaseService` 读写 sqlite。
4. controller 使用统一 `Result` 返回结果。

## 开发要点

- 服务器配置属于持久化数据，必须通过 repository 层访问。
- 修改模型字段时要同步 `server_config.dart`、数据库读写逻辑和前端类型。
- 如涉及敏感字段，应明确是否允许持久化；默认不要保存密码、私钥明文或 token。
- 删除配置不应影响当前已经建立的 SSH 运行态会话，除非产品行为明确要求。
