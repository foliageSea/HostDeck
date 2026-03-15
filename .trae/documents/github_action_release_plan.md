# 计划：添加 Github Action 自动发布 Win/Mac/Linux/Android 版本并集成 Shelf 静态托管

该计划概述了为 SSH 工具添加自动构建和发布流程的步骤，包括构建 Vue.js 前端，将其嵌入 Flutter 应用，并通过 `shelf_static` 进行托管。

## 1. 依赖和配置

* [ ] 在 `pubspec.yaml` 中添加 `path_provider` 和 `shelf_static` 依赖。

* [ ] 更新 `pubspec.yaml` 的 `assets` 部分，包含 `assets/web/` 目录。

* [ ] 创建 `assets/web/` 目录（如果需要，添加 `.gitkeep` 确保存在，构建过程会自动填充该目录）。

## 2. 前端集成逻辑 (Dart)

* [ ] 创建 `lib/utils/asset_extractor.dart`：

  * 实现 `extractWebAssets()` 函数，检查 `assets/web` 是否已解压到 `getApplicationSupportDirectory()`。

  * 如果未解压（或版本变更），从 `rootBundle`（资源包）复制文件到目标目录。

  * 返回解压后的 `web` 目录路径。

* [ ] 修改 `lib/server/server_service.dart`：

  * 在启动时调用 `extractWebAssets()`。

  * 使用 `shelf_static` 的 `createStaticHandler` 创建静态文件处理器。

  * 更新请求处理管道，使用 `Cascade`（级联）：

    * 优先处理 `apiRoutes`。

    * 其次处理静态文件。

    * 最后处理 SPA 回退（对于非 API 的未知路由，返回 `index.html`）。

## 3. GitHub Action 工作流 (`.github/workflows/release.yml`)

* [ ] 定义在 `v*` 标签推送时触发的工作流。

* [ ] **Job 1: 构建前端 (Build Frontend)**

  * 环境：`ubuntu-latest`。

  * 步骤：检出代码，安装 Node.js，安装依赖 (`pnpm`)，构建 (`pnpm build`)，上传构建产物 (`dist` 目录)。

* [ ] **Job 2: 构建 Windows 版本**

  * 环境：`windows-latest`。

  * 步骤：检出代码，下载前端产物，复制到 `assets/web`，安装 Flutter，构建 (`flutter build windows --release`)，压缩，上传发布资源。

* [ ] **Job 3: 构建 Linux 版本**

  * 环境：`ubuntu-latest`。

  * 步骤：检出代码，下载前端产物，复制到 `assets/web`，安装 Linux 依赖 (GTK 等)，安装 Flutter，构建 (`flutter build linux --release`)，压缩，上传发布资源。

* [ ] **Job 4: 构建 macOS 版本**

  * 环境：`macos-latest`。

  * 步骤：检出代码，下载前端产物，复制到 `assets/web`，安装 Flutter，构建 (`flutter build macos --release`)，创建 DMG 或 Zip，上传发布资源。

* [ ] **Job 5: 构建 Android 版本**

  * 环境：`ubuntu-latest`。

  * 步骤：检出代码，下载前端产物，复制到 `assets/web`，设置 Java/Flutter，构建 (`flutter build apk --release`)，上传发布资源。

## 4. 验证

* [ ] 验证 `pubspec.yaml` 的更改。

* [ ] 验证 `server_service.dart` 的逻辑（可在本地手动放置文件到 `assets/web` 进行测试）。

