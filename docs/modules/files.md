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
- `POST /api/files/upload`：上传文件。
- `POST /api/files/batch-download`：批量下载。
- `POST /api/files/rename`：重命名。
- `POST /api/files/mkdir`：创建目录。
- `POST /api/files/copy`：复制。
- `POST /api/files/extract`：解压。

## 开发要点

- 文件操作依赖 SSH 会话，必须处理会话过期和远端权限错误。
- 文本读写、上传、下载、批量下载可能有不同响应类型，前端 API 封装要明确 `responseType`。
- 路径处理优先复用 `src/utils/path.ts`，避免在组件中重复拼接路径。
- 文件选择器组件有测试覆盖，改动时关注 `FilePickerDialog.spec.ts`。
- 删除、覆盖、批量操作等危险操作应通过 `src/lib/ui.ts` 的确认框完成。

## 相关测试

- `host-deck-ui/src/views/Files/components/__tests__/FilePickerDialog.spec.ts`
