# 测试与校验

本文档记录项目常用验证命令和变更类型对应的测试范围。

## 后端与桌面校验

仓库根目录执行：

```bash
dart format .
flutter analyze
flutter test
```

单个测试文件示例：

```bash
flutter test test/monitor_service_test.dart
```

按测试名称执行示例：

```bash
flutter test --name "MonitorService parses system status correctly"
```

## 前端校验

前端构建：

```bash
pnpm --dir host-deck-ui build
```

前端类型检查：

```bash
pnpm --dir host-deck-ui exec vue-tsc -p tsconfig.app.json --noEmit
```

前端测试：

```bash
pnpm --dir host-deck-ui test
```

单个前端测试示例：

```bash
pnpm --dir host-deck-ui exec vitest run src/views/Files/components/__tests__/FilePickerDialog.spec.ts
```

## 当前测试索引

后端/Flutter 测试：

- `test/ssh_operation_limiter_test.dart`
- `test/monitor_service_test.dart`
- `test/docker_engine_mapper_test.dart`
- `test/monitor_history_service_test.dart`
- `test/widget_test.dart`

前端测试：

- `host-deck-ui/src/views/Files/components/__tests__/FilePickerDialog.spec.ts`

## 变更对应的最低验证

后端 Dart 代码变更：

- `dart format .`
- `flutter analyze`
- 相关 `flutter test ...`

前端代码变更：

- `pnpm --dir host-deck-ui build`
- 涉及类型边界时运行 `vue-tsc`
- 涉及已有测试组件时运行相关 `vitest`

API 合约变更：

- 同步 controller、routes、service、前端 `src/api/*` 和调用点。
- 确认 `src/lib/http.ts` 的统一解包仍匹配。
- 运行后端相关测试和前端构建。

打包链路变更：

- 核对 `Dockerfile`、`.github/workflows/release.yml`、`pubspec.yaml`、构建脚本。
- 至少运行相关构建命令或说明无法运行的原因。

纯文档变更：

- 不需要运行代码构建。
- 应检查文档中的路径、命令、端口和当前代码是否一致。
