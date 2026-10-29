# code-server 分发与部署调研

> task-3｜面向 HostDeck 现有分发形态，给出 code-server 的安装/运行/升级方案。仓库事实带 file:line，上游事实带来源。
> 说明：本机 web_search/web_fetch 不可用，上游事实由 lead 用 shell curl 核实；task 后由 lead 收口。

> 决策收敛补充（2026-10-29）：IDE 只服务 SSH 目标 Linux 主机；默认走**离线包**，不再默认运行时从 GitHub 下载；多会话要求固定同一 code-server 版本。详见 [remote-implementation-plan.md](remote-implementation-plan.md)。

## 1. 现有分发形态（仓库事实）

| 形态 | 产物 | 服务入口与数据目录 |
| --- | --- | --- |
| Docker | Dockerfile 多阶段构建，最终 debian:bookworm-slim，复制 server bundle 到 /app、web 到 /app/web；EXPOSE 8080；VOLUME /data；CMD --host 0.0.0.0 --data-dir /data | 数据持久化在 /data（Dockerfile:56-64） |
| Electron Windows | NSIS/zip；extraResources 打包 server/ 与 web/ | 运行时以 --data-dir <userData>/data 启动（host-deck-electron/package.json:50-72、src/main/server-runtime.cjs:95-101） |
| Electron macOS arm64 | dmg/zip，同上 | 同上 |
| Windows CLI zip | dart build cli 产物 + web/，默认端口 18080 | 通过 --data-dir 指定；默认静态资源在 exe 旁 ../web（scripts/build_server.ps1、server_cli.dart:82-86） |
| Linux 原生/CLI | ./scripts/build_server.sh 产物；也可 dart run bin/server.dart | --data-dir；默认 127.0.0.1:8080 |
| 发布流水线 | .github/workflows/release.yml：web → CLI zip / Docker / Electron win+mac（Flutter release job 已注释） | — |

关键约束：

- Electron 安装包已包含 server + web；再加 219MB 压缩/676MB 解压的 code-server 会显著膨胀，不应随包分发。
- Docker 镜像当前为几百 MB；内置 code-server 会让镜像 +~700MB，应做成可选构建参数或运行时下载到 /data。
- 所有形态的数据目录都可通过 --data-dir / userData 定位，适合放 code-server 的二进制、用户数据与扩展。

## 2. 三类部署拓扑

| 拓扑 | code-server 位置 | 文件系统 | 网络路径 | 适用 | 主要问题 |
| --- | --- | --- | --- | --- | --- |
| T1 同机 | HostDeck 所在机 | 本机 | 127.0.0.1:<port> | 桌面/自托管单机、Linux/macOS | Windows 原生待测；Docker 内只编辑容器文件系统（除非挂卷） |
| T2 远端 SSH | SSH 目标机 | 目标机 | HostDeck → SSH direct-tcpip → 目标 127.0.0.1:<port> | 最契合 HostDeck 远程主机工作台 | 安装/版本/端口/租约/性能；目标需 Linux/macOS（Windows 目标少见） |
| T3 外部实例/容器 sidecar | 用户已有实例或 compose 服务 | 取决于挂载 | 后端 HTTP（可能 TLS） | 企业已有 code-server、Docker 共享卷 | 认证/版本/SSRF/TLS；文件系统可能不是 SSH 目标 |

## 3. 各平台可行性

| 平台 | 方式 | 结论 |
| --- | --- | --- |
| Linux x64/arm64 | standalone tar.gz（自带 Node） | ✅ glibc ≥ 2.28；HostDeck Docker 的 bookworm（glibc 2.36）满足；Alpine/musl 需 npm 或 Docker |
| macOS x64/arm64 | standalone tar.gz | ✅；Electron 子进程可执行；无需额外运行时 |
| Windows x64 | standalone windows-amd64 包 | ⚠️ 自 v4.137.0 起随 release 发布（v4.143.1 有资产），但官方 docs/install.md 仍写「不发布 Windows 版本」，需实机验证；失败则引导 WSL2 / Docker Desktop / 连远端 Linux HostDeck |
| Windows arm64 | 无官方包 | ❌ 走远端或 WSL |
| 无网/内网 | 离线包 + 本地路径导入；或镜像内置 | ✅ 需要可配置下载源与校验值 |

体积/资源（实测 + 上游数据）：

- linux-amd64 tar.gz 219MB，解压 676MB；macOS/Windows 包 195～234MB。
- 运行内存通常 0.5～1GB 量级（视扩展/工作区而定），启动数秒。
- 因此：按需安装、可卸载、显示占用；不建议随 HostDeck 主安装包捆绑。

## 4. 推荐分发策略

### 4.1 统一原则

1. 版本锁定 + sha256 校验：固定 code-server-<version>-<platform>.tar.gz，下载后校验，失败回滚。
2. 可配下载源：默认 GitHub Release，支持镜像/内网地址；企业可预置离线包。
3. 不自动升级：运行时 --disable-update-check；升级由 HostDeck 显式操作。
4. 数据目录分离：<dataDir>/code-server/{bin,data,extensions,logs}；删除版本不影响用户数据。
5. 权限最小化：本机以当前用户运行；远端安装到用户目录，不用 sudo。

### 4.2 Docker

- A. 运行时下载（推荐默认）：镜像不内置，首次启用时下载到 /data/code-server；镜像体积不变，但容器需外网/镜像源。
- B. 构建参数内置：--build-arg INSTALL_CODE_SERVER=true 在 runtime 阶段解压到 /opt/code-server；镜像 +~700MB，适合离线/内网。
- C. sidecar：compose 增加 codercom/code-server，共享 workspace 卷，HostDeck 代理到 http://code-server:8080；只适合「编辑共享卷」场景，不能编辑任意 SSH 目标。
- 端口：code-server 仅监听容器内 127.0.0.1 或 compose 内网，不映射到宿主机；由 HostDeck 反代。
- 权限：容器内以 root 运行的 code-server 会以 root 编辑挂载卷，需显式降权/用户映射。

### 4.3 Electron

- 不打包 code-server；首次启用下载到 <userData>/data/code-server（与 server 的 --data-dir 一致）。
- Windows 先走 219MB 的 windows-amd64 包实测；若不可用，UI 提示「使用 WSL2/Docker 或连接远端 HostDeck」。
- macOS arm64 使用 macos-arm64 包；下载后 chmod +x，由 Dart Process.start 拉起，不经过 Finder/Gatekeeper 的隔离属性（需实测）。
- 端口：Electron 内 HostDeck server 默认 18080（server-runtime.cjs:15-18），code-server 默认端口应避开（建议 18090+ 或动态探测）。

### 4.4 Windows CLI zip

- 同一套运行时下载逻辑；数据目录由 --data-dir 指定，需在启动脚本/文档中固定，避免升级丢失。
- 若 code-server Windows 包不可用，明确降级路径，不阻塞 HostDeck 主功能。

## 5. 升级与合规

- 升级：下载新版本 → 校验 → 停旧进程 → 切换 bin/current 符号链接/目录 → 启动健康检查 → 失败回滚。保留上一版本。
- 兼容性冒烟：首屏、静态资源、WS、内置终端、扩展安装、文件保存。
- 许可证：code-server MIT；VS Code 核心 MIT；扩展各自许可证；不能使用 Microsoft Marketplace（Open VSX only）。
- 若镜像/安装包内置 code-server，必须在 THIRD_PARTY_NOTICES.md 增加 code-server 及其依赖的许可证文本，并保留 LICENSE / ThirdPartyNotices.txt。

## 6. 风险清单

| # | 风险 | 缓解 |
| --- | --- | --- |
| 1 | 676MB 解压 + 0.5～1GB 内存 | 按需安装/远端优先/显示占用/可卸载 |
| 2 | Windows 支持不确定 | 实机 PoC；WSL/Docker/远端降级 |
| 3 | 下载失败/内网无外网 | 可配镜像、离线包导入、镜像内置构建参数 |
| 4 | Docker 内编辑的不是 SSH 目标 | 默认推荐 T2；T1 仅在挂载卷时宣传 |
| 5 | 以 root 运行编辑挂载卷 | 降权/用户映射，文档警示 |
| 6 | 升级破坏子路径/接口 | 锁版本 + 冒烟 + 回滚 |
| 7 | 供应链 | sha256、固定版本、可信源 |
| 8 | 许可合规 | THIRD_PARTY_NOTICES、保留上游 LICENSE |


## 7. 决策后调整（远端 Linux / 离线包 / 多会话）

### 7.1 发布资产

- 每个 HostDeck 版本发布两个离线包：`hostdeck-code-server-<csVersion>-linux-amd64.tar.gz`、`...-linux-arm64.tar.gz`。
- 同时发布清单 `hostdeck-code-server-<csVersion>.json`（arch、size、sha256、minGlibc、license）与 `SHA256SUMS`。
- 可选发布 `hostdeck-code-server-offline-<csVersion>.zip`（含两个架构 + 清单 + LICENSE/ThirdPartyNotices），方便内网一次性下载。
- 主安装包（Electron/CLI/Docker）默认不捆绑；Docker 提供 `--build-arg CODE_SERVER_OFFLINE_DIR=...` 将离线包拷入镜像。

### 7.2 安装来源

- 首选：管理端在 HostDeck 设置页上传离线包 → 存 `<dataDir>/code-server/packages/`。
- 其次：管理员把包放入 `<dataDir>/code-server/offline/` 后点“扫描导入”。
- 兼容：`--code-server-offline-dir` 指定只读目录（Docker 挂载卷）。
- 不再默认访问 GitHub；需要联网下载时作为显式可选项，且必须校验 sha256。

### 7.3 平台收敛

- 只关心远端 Linux：x86_64→amd64、aarch64→arm64；armv7/i686 不支持。
- glibc ≥ 2.28；Alpine/musl、CentOS 7 等旧 glibc 不支持 standalone，UI 需明确报错并给出替代方案。
- HostDeck 自身跑在 Windows/macOS/Linux 均可；Electron Windows 不再需要 code-server Windows 包，原先的 Windows 实测风险消失。

### 7.4 多会话

- 所有会话固定同一 code-server 版本（发布资产版本号统一），避免同源 Service Worker/静态资源版本冲突。
- 启动参数加 `--enable-remote-storage`，工作台状态写入各目标自己的 user-data-dir；远端存储初始化失败会回退浏览器存储，需在日志/UI 提示。
- 每个 SSH 连接一个会话；远端目录按 hostKey 隔离；单目标重复打开窗口复用同一会话。

### 7.5 Docker/Electron 具体建议

| 形态 | 建议 |
| --- | --- |
| Docker | 离线包放 `/data/code-server/packages`（持久卷）或镜像构建期拷入 `/opt/code-server/offline`；不要映射 code-server 端口 |
| Electron Windows | 不打包 code-server；通过 UI 上传离线包；HostDeck 仅作为 SSH 客户端/代理 |
| Electron macOS | 同上；离线包存 `<userData>/data/code-server/packages` |
| Windows CLI | 数据目录显式 `--data-dir`；离线包与安装元数据随 dataDir 持久化 |
