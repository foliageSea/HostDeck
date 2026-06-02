# 文本编辑与媒体预览模块

文本编辑与媒体预览模块用于从文件管理器打开远端文件，提供文本编辑、图片预览和视频预览能力。

## 代码入口

前端：

- `host-deck-ui/src/views/TextEditor/index.vue`
- `host-deck-ui/src/views/MediaViewer/index.vue`
- `host-deck-ui/src/components/editor/CodeEditor.vue`
- `host-deck-ui/src/lib/monaco.ts`
- `host-deck-ui/src/api/files.ts`

相关模块：

- `docs/modules/files.md`
- `docs/modules/desktop-shell.md`

## 开发要点

- 文本内容读写复用文件模块 API。
- 编辑器能力集中在 `CodeEditor.vue` 和 `lib/monaco.ts`。
- 大文件、二进制文件和不可识别编码应有明确错误提示或降级展示。
- 媒体预览使用前端播放器能力，需关注资源 URL、加载失败和窗口关闭释放。
- 从文件管理器打开文件时，应通过桌面工作台创建或聚焦对应窗口。

## 修改建议

- 新增文本语言支持时，优先调整 Monaco 初始化和文件类型识别逻辑。
- 新增媒体类型时，先确认浏览器或播放器是否原生支持，再扩展预览入口。
- 保存行为必须处理远端写入失败和会话失效。
