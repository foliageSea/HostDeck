# 文件管理模块

文件管理模块负责远端目录浏览、文件读写、上传、下载、重命名、复制、删除、解压和目录创建。

## 代码入口

后端：

- `lib/server/features/files/file_controller.dart`
- `lib/server/features/files/file_service.dart`
- `lib/server/core/ssh/ssh_service.dart`
- `lib/server/core/ssh/ssh_repository.dart`
- `lib/server/features/files/file_item.dart`

前端：

- `host-deck-ui/src/api/files.ts`
- `host-deck-ui/src/views/Files/index.vue`
- `host-deck-ui/src/views/Files/components/FileBrowserContent.vue`
- `host-deck-ui/src/views/Files/components/FilePickerDialog.vue`
- `host-deck-ui/src/views/Files/components/FileNameDialog.vue`
- `host-deck-ui/src/views/Files/components/FileFavoriteSidebar.vue`
- `host-deck-ui/src/stores/file.ts`
- `host-deck-ui/src/stores/file-clipboard.ts`
- `host-deck-ui/src/stores/upload-center.ts`
- `host-deck-ui/src/utils/path.ts`

## API

- `GET /api/files/list`：列出目录。
- `POST /api/files/session`：创建文件会话。
- `DELETE /api/files/session`：关闭文件会话。
- `GET /api/files/read`：读取文件内容。
- `POST /api/files/write`：写入文件内容。
- `POST /api/files/delete`：删除文件或目录。
- `POST /api/files/upload`：流式上传文件。远端拒绝写入时返回具体错误（例如 SSH 用户无写入权限为 HTTP 403），任务中心展示服务端消息。
- `POST /api/files/batch-download`：批量下载。
- `POST /api/files/rename`：重命名。
- `POST /api/files/mkdir`：创建目录。
- `POST /api/files/copy`：复制。
- `POST /api/files/extract`：同步解压（旧接口）。
- `POST /api/files/tasks?connectionId=<id>`：创建复制、移动、压缩、解压或删除任务，提交 `{type, items:[{sourcePath,targetPath}]}`。
- `GET /api/files/tasks` / `GET /api/files/tasks/<id>`：查看任务列表或详情。
- `POST /api/files/tasks/<id>/cancel`：请求中断。运行中请求返回当前快照，最终结果以事件或详情为准。
- `GET /api/files/tasks/<id>/events`：SSE 首帧为当前快照，进度事件为 `task`，终态为 `done`。任务项可含 `progress`（阶段、已处理/总字节、已处理/总条目），未知总量为 `null`，旧记录无进度。

## 文件任务 SideCar

复制、移动、压缩和解压在 SSH 目标机本地执行，文件数据不经过 HostDeck。带资产的正式发布默认启用：首次使用时，HostDeck 通过现有连接将匹配的 AOT 二进制安装到当前 SSH 用户的 HOME 下，默认位置为 `~/.local/lib/hostdeck/file-sidecar/<sha256>/`。若其中的 `.local`、`lib` 或 `hostdeck` 目录由当前用户拥有且仅同组额外拥有写权限，则改用 `~/.hostdeck-file-sidecar/<sha256>/`，不修改现有目录的权限。两处缓存均要求私有目录权限为 `0700`，并按内容哈希复用。无需 sudo、Dart SDK、常驻服务、开放端口或目标机访问外网。

- **远端平台：**Linux x86_64 / arm64（glibc ≥ 2.35），要求支持 statx 与文件系统的无覆盖原子重命名。首次使用需要可写、可执行的用户目录及常见 POSIX 管理工具（包括 SHA-256 校验）。
- **归档：**压缩支持 ZIP 和 TAR.GZ（含 TGZ），解压还支持 TAR。TAR.BZ2/TAR.XZ 及其别名继续使用旧路径。压缩会保存符号链接本身，不读取链接指向的文件。解压只恢复指向解压目录内已有普通文件或目录的相对符号链接；拒绝绝对链接、越界链接、悬空链接、经其他链接解析的路径、硬链接、特殊文件和路径冲突。包含外部依赖链接的源码可压缩，但这样的链接不会通过 SideCar 解压验证；如需制作可往返的源码归档，请先排除 `.plugin_symlinks` 等生成目录。保存链接不等于打包其依赖。复制和移动仍不跟随或处理符号链接。归档最多处理 100,000 个条目、单文件 64 GiB、总展开 100 GiB；不应用归档所有者或特权权限。归档操作会在目标磁盘为源数据创建临时副本，请预留空间。要在 HostDeck 中使用 code-server，仍推荐走 [IDE 离线包安装](code-server.md)。
- **落盘：**SideCar 目标是完整路径，父目录必须已经存在、目标不得存在，不覆盖、不合并。复制/归档/解压先写私有暂存目录再发布目标。同盘移动保留原 inode 和元数据；跨盘移动在目标提交后清理来源，若清理失败会明确报告，可能保留部分来源。操作前请停止其他进程修改来源；这不是快照备份工具。
- **进度：**任务中心显示阶段和实际字节/条目。流式 TAR 解压无法事先知道展开总量，只展示已处理值；同盘重命名无需等待复制进度。只有成功才显示 100%。关闭文件窗口不影响任务继续执行。
- **兼容：**没有 SideCar 资产、不支持的平台或显式关闭时沿用旧执行方式，标记“兼容模式”，没有可靠的实时进度或同样的落盘语义。启动 SideCar 操作后，协议、断线或执行失败不会自动重试。已落盘的操作不会因为收到晚到的取消请求而回滚；无法确认时任务失败并提示检查目标机。

用 `HOSTDECK_FILE_SIDECAR=off` 关闭自动部署与执行，或通过 `HOSTDECK_FILE_SIDECAR_DIR` 指定可信资产目录（含 manifest 和二进制）。未指定时，查找服务 bundle 下的 `sidecars/`。见[打包方式](../build-and-release.md#文件-sidecar-资产)。

### 独立 CLI

```sh
./hostdeck-file-sidecar-linux-amd64 copy '/data/源目录' '/data/副本'
./hostdeck-file-sidecar-linux-amd64 move '/data/副本' '/backup/目录'
./hostdeck-file-sidecar-linux-amd64 compress '/data/源目录' '/backup/目录.tar.gz'
./hostdeck-file-sidecar-linux-amd64 extract '/backup/目录.tar.gz' '/restore/输出目录'
```

CLI 将进度写到 stderr。退出码 0 为成功，1 为操作失败，2 为用法或协议错误，130 为取消。HostDeck 使用 `run --stdio`：stdin 输入一次带 ID 的 `run` 帧并保持开放（后续接受 `ping`、`cancel`）；stdout 输出 LF 分隔的 UTF-8 JSON 帧（`started`、`progress`、`heartbeat`、唯一的 `result`）。

## 开发要点

- 文件操作依赖 SSH 会话，必须处理会话过期和远端权限错误。
- 文本读写、上传、下载、批量下载可能有不同响应类型，前端 API 封装要明确 `responseType`。
- 路径处理优先复用 `src/utils/path.ts`，避免在组件中重复拼接路径。
- 文件选择器组件有测试覆盖，改动时关注 `FilePickerDialog.spec.ts`。
- 删除、覆盖、批量操作等危险操作应通过 `src/lib/ui.ts` 的确认框完成。

## 相关测试

- [文件选择器](../../host-deck-ui/src/views/Files/components/__tests__/FilePickerDialog.spec.ts)、[任务中心进度](../../host-deck-ui/src/views/TaskCenter/file-task-progress.spec.ts)、[任务订阅](../../host-deck-ui/src/stores/__tests__/upload-center.spec.ts)。
- [SideCar 单元测试](../../host-deck-sidecar/test/)：在纯 Dart 包目录运行 dart test，覆盖协议、文件操作和归档。
- [OpenSSH 集成测试](../../test/file_sidecar_openssh_integration_test.dart)：对一次性的本机 OpenSSH 测试账号运行。设置 HOSTDECK_TEST_SIDECAR_SSH_PORT、HOSTDECK_TEST_SIDECAR_SSH_USER、HOSTDECK_TEST_SIDECAR_SSH_KEY（私钥文件路径）和 HOSTDECK_TEST_SIDECAR_ASSETS（资产目录），再运行 fvm flutter test test/file_sidecar_openssh_integration_test.dart。
