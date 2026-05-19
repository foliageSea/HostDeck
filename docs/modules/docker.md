# Docker 模块

Docker 模块负责通过 SSH 连接访问远端 Docker Engine，提供容器、镜像、网络、卷和 Compose 项目管理能力。

## 代码入口

后端：

- `lib/server/controllers/docker_controller.dart`
- `lib/server/services/docker_service.dart`
- `lib/server/services/docker_engine_mapper.dart`
- `lib/server/repositories/docker_engine_repository.dart`
- `lib/server/repositories/ssh_repository.dart`
- `lib/server/models/docker_container.dart`
- `lib/server/models/docker_image.dart`
- `lib/server/models/docker_network.dart`
- `lib/server/models/docker_volume.dart`

前端：

- `ssh-tool-ui-next/src/api/docker.ts`
- `ssh-tool-ui-next/src/views/Docker/index.vue`
- `ssh-tool-ui-next/src/views/Docker/components/*`
- `ssh-tool-ui-next/src/views/Docker/hooks/useDockerView.ts`
- `ssh-tool-ui-next/src/views/Docker/hooks/dockerViewColumns.ts`
- `ssh-tool-ui-next/src/views/Docker/hooks/dockerViewHelpers.ts`
- `ssh-tool-ui-next/src/views/Docker/hooks/dockerViewTypes.ts`

## API 分组

会话与可用性：

- `POST /api/docker/session`
- `DELETE /api/docker/session`
- `GET /api/docker/check`
- `GET /api/docker/compose/check`

Compose：

- `GET /api/docker/compose/projects`
- `POST /api/docker/compose/project`
- `POST /api/docker/compose/project/services`
- `POST /api/docker/compose/project/up`
- `POST /api/docker/compose/project/stop`
- `POST /api/docker/compose/project/restart`
- `POST /api/docker/compose/project/down`
- `POST /api/docker/compose/project/logs`

容器：

- `GET /api/docker/containers`
- `GET /api/docker/containers/<id>/inspect`
- `GET /api/docker/containers/<id>/stats`
- `POST /api/docker/containers/<id>/shell`
- `POST /api/docker/containers/<id>/start`
- `POST /api/docker/containers/<id>/stop`
- `POST /api/docker/containers/<id>/restart`
- `POST /api/docker/containers/<id>/pause`
- `POST /api/docker/containers/<id>/unpause`
- `POST /api/docker/containers/<id>/rename`
- `POST /api/docker/containers/<id>/recreate`
- `DELETE /api/docker/containers/<id>`
- `POST /api/docker/containers`
- `GET /api/docker/containers/logs`
- `POST /api/docker/containers/diagnostics`
- `POST /api/docker/containers/batch-start`
- `POST /api/docker/containers/batch-stop`
- `DELETE /api/docker/containers/stopped`

镜像：

- `GET /api/docker/images`
- `POST /api/docker/images/prune`
- `DELETE /api/docker/images/<id>`
- `POST /api/docker/images/pull`
- `POST /api/docker/images/import`
- `POST /api/docker/images/tag`
- `GET /api/docker/images/<id>/export`
- `GET /api/docker/images/<id>/history`
- `GET /api/docker/images/<id>/create-defaults`
- `GET /api/docker/images/<id>/containers`

网络：

- `GET /api/docker/networks`
- `POST /api/docker/networks`
- `GET /api/docker/networks/<id>/inspect`
- `POST /api/docker/networks/<id>/connect`
- `POST /api/docker/networks/<id>/disconnect`
- `DELETE /api/docker/networks/<id>`
- `POST /api/docker/networks/prune`

卷：

- `GET /api/docker/volumes`
- `POST /api/docker/volumes`
- `GET /api/docker/volumes/<name>/inspect`
- `DELETE /api/docker/volumes/<name>`
- `POST /api/docker/volumes/prune`

## 开发要点

- `DockerService` 承载业务流程，`DockerEngineRepository` 承载 Docker Engine 命令或接口访问。
- `DockerEngineMapper` 负责把 Docker Engine 输出映射为项目模型，新增字段时优先补充 mapper 和测试。
- Docker 操作依赖 SSH 会话，应处理 Docker 未安装、权限不足、daemon 未启动、Compose 不可用等状态。
- 删除、清理、重建等危险操作前端应提供明确确认。
- 容器 shell 会话与终端模块有关，修改时要同时关注终端会话生命周期。

## 相关测试

- `test/docker_engine_mapper_test.dart`
