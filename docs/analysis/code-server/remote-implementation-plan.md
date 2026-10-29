# HostDeck × code-server 实施方案（决策收敛版）

> 2026-10-29｜基于已确认的四项产品约束：只编辑 SSH 目标主机、目标均为 Linux、提供离线安装包、支持多 IDE 会话。
> 主分析见 [code-server-feasibility.md](../code-server-feasibility.md)；本文件是可直接排期的落地设计。

## 1. 已确认约束

| # | 决策 | 对方案的影响 |
| --- | --- | --- |
| 1 | IDE 编辑 **SSH 目标主机** | 不实现本机 provider；所有 IDE 会话都经由 SSH 隧道 + 同源反代；文件系统与终端/文件管理一致 |
| 2 | SSH 目标 **全部是 Linux** | 只需适配 linux-amd64/arm64；HostDeck 本身跑在 Windows/macOS/Linux 都不影响 IDE |
| 3 | **提供离线包** | 不依赖远端联网；HostDeck 发布离线包，管理端上传/内置，经 SSH 推送到目标机安装 |
| 4 | **支持多会话** | 每个 SSH 连接可同时开 IDE；用 code-server 的 enable-remote-storage 把工作台状态持久化到各自远端，规避同源浏览器存储冲突 |

隐含前提（需保持）：HostDeck 访问认证为单管理员；SSH 目标允许本地端口转发（direct-tcpip）；目标用户对 HOME 有写权限。

## 2. 总体架构

text
Browser (HostDeck SPA, 同源)
  └─ iframe /ide/<sessionId>/?folder=<path>
        │
        ▼
shelf Pipeline
  ├─ accessLog / sshActivity
  ├─ IdeProxyMiddleware
  │    ├─ 鉴权（hostdeck_session / Bearer）
  │    ├─ HTTP：HttpClient(autoUncompress=false) → 127.0.0.1:<bridgePort>
  │    └─ WS：request.hijack → 原始 socket ↔ 127.0.0.1:<bridgePort>
  └─ Cascade(api → static → SPA)
        │
  LoopbackSshBridge（每会话一个 127.0.0.1:0 监听）
        │  direct-tcpip
        ▼
  远端 Linux：code-server --bind-addr 127.0.0.1:<port> --auth none
              --enable-remote-storage
              --user-data-dir ~/.local/share/hostdeck/code-server/<hostKey>/data
              --extensions-dir .../extensions

核心模块：

- IdePackageStore：离线包缓存、上传、校验、版本/架构元数据。
- RemoteIdeInstaller：远端预检、传输、解压、版本校验、升级/卸载。
- IdeSessionManager：会话注册、端口分配、进程启停、租约、异常恢复。
- IdeProxy：/ide/<sessionId>/ 同源反代（HTTP + WS），剥离前缀。
- LoopbackSshBridge：本地监听 → SSH direct-tcpip，复用 docker_socket_tunnel_service 的形态。
- 前端 CodeServerView：加载/安装/启动/错误/多会话状态。

## 3. 远端 Linux 适配

### 3.1 预检（安装前）

| 检查 | 命令/方式 | 不满足时 |
| --- | --- | --- |
| 架构 | uname -m → x86_64=amd64，aarch64/arm64=arm64 | 其他架构（armv7l、i686）不支持，提示无官方包 |
| libc | ldd --version 或 getconf GNU_LIBC_VERSION，glibc ≥ 2.28 | Alpine/musl 与 CentOS 7 等旧 glibc 不支持 standalone；提示改用 Docker/自建 npm，或放弃 |
| 磁盘 | df -Pk $HOME，需 ≥ 1.5GB 可用（219MB 包 + 676MB 解压 + 余量） | 阻止安装并显示所需空间 |
| 工具 | tar、gzip、sha256sum、setsid/nohup、chmod | 缺 tar/setsid 时提示；sha256sum 可选（SSH 已保证传输完整性） |
| 可执行挂载 | 安装后执行 bin/code-server --version | noexec 的 HOME 会失败，需提示更换目录 |
| 端口转发 | 现有 SSH 连接可用即满足 | AllowTcpForwarding=no 时直接报错 |

### 3.2 远端目录

- 版本目录：~/.local/lib/hostdeck/code-server/<version>/
- 数据目录：~/.local/share/hostdeck/code-server/<hostKey>/{data,extensions,logs}
- 会话文件：.../<hostKey>/sessions/<sessionId>.json（记录 pid、port、版本、启动时间）
- hostKey = sha256(user@host:port)[0:12]，同一目标重连可复用配置与扩展
- 不写系统目录、不需要 sudo

### 3.3 启动参数

text
PASSWORD 不设置（--auth none，仅 loopback）
bin/code-server
  --auth none
  --bind-addr 127.0.0.1:<port>
  --enable-remote-storage
  --disable-telemetry
  --disable-update-check
  --disable-workspace-trust
  --user-data-dir <data>
  --extensions-dir <extensions>
  --locale zh-cn

工作区通过 iframe URL 的 ?folder=<path> 打开（code-server 支持 workspace/folder 查询参数）。

### 3.4 端口选择

- 从 18090 + (hostKey 哈希 % 100) 开始尝试，最多 +10。
- 启动后经由 bridge 请求 /healthz 判定成功；失败读日志（端口占用/参数错误）后递增重试。
- 不使用 8080/18080（HostDeck 自身/Electron server 可能占用）。

## 4. 离线包流水线

### 4.1 包格式与来源

- 文件：hostdeck-code-server-<csVersion>-linux-<arch>.tar.gz，内含官方 standalone 目录结构（bin/code-server、lib、node 等）。
- 清单：hostdeck-code-server-<csVersion>.json，字段：csVersion、arch、size、sha256、minGlibc、license、createdAt。
- 来源：HostDeck GitHub Release 资产（与主程序同版本发布）；或管理员自行上传同结构离线包。
- 不在 HostDeck 主安装包/Electron 包内捆绑（体积原因）；Docker 可用挂载或构建参数内置。

### 4.2 上传与缓存（HostDeck 服务端）

- 新接口 POST /api/code-server/packages（multipart），流式写临时文件，边写边算 sha256，限制单包 ≤ 500MB，完成后原子改名。
- 校验：清单存在时比对 sha256/size/arch；无清单则记录自算 sha256，要求管理员确认。
- 存储：<dataDir>/code-server/packages/<csVersion>/linux-<arch>.tar.gz + manifest.json。
- 列表/删除/占用统计：GET/DELETE /api/code-server/packages；UI 在设置页管理。
- 支持“扫描离线目录”：管理员把包放到 <dataDir>/code-server/offline/ 后点击导入。

### 4.3 推送到远端

1. 预检（§3.1）并确认目标架构对应包存在。
2. 创建 ~/.local/lib/hostdeck/code-server/<version>.partial。
3. 传输 + 解压（二选一，按实现成本选 SFTP 或流式 exec）：
   - SFTP：sftp.open 写分块（可断点续传），完成后远端 sha256sum 校验，再 tar -xzf。
   - 流式：SSH exec 执行 tar -xz -C <dir>，HostDeck 端把 tar.gz 流写入 stdin（需新增 execStream，现有 execWithResult 的 stdin 是 String，不能传二进制）。
4. 校验 bin/code-server --version == 期望版本；写 .installed.json（版本、sha256、安装时间）。
5. 失败清理 .partial；SSE 上报阶段/字节数/错误。
6. 升级：装到新版本目录 → 停会话 → 切换 current 指针 → 健康检查 → 失败回滚旧版本。

### 4.4 无外网环境的边界

- 安装/升级完全离线可用；扩展市场仍需要远端能访问 Open VSX。
- 完全离线场景：后续支持 VSIX 上传安装（不在本期范围，文档标注）。
- code-server 自身禁止 update check。

## 5. 会话与多会话

### 5.1 会话模型

| 字段 | 说明 |
| --- | --- |
| sessionId | 随机 12 hex，用于 /ide/<sessionId>/，不可猜测 |
| connectionId | HostDeck SSH 连接 |
| hostKey | 稳定目标标识，用于远端数据目录 |
| csVersion / port / pid | 远端实例信息 |
| bridgePort | HostDeck 本地 127.0.0.1 监听端口 |
| state | installing / starting / running / stopping / error / stopped |
| folder | 打开的工作区路径 |

- 每个 SSH 连接最多一个 IDE 会话（同一目标再次打开窗口复用）；不同连接可并行。
- 会话注册表在内存 + sqlite（重启后可依据远端 sessions/*.json 与 /healthz 接管或清理）。
- 上限可配置（默认 4），超过时拒绝并提示。

### 5.2 多会话隔离

- 同源路径 /ide/<sessionId>/ 共享浏览器 origin。启用 --enable-remote-storage 后，工作台 settings/state 持久化到各自远端的 user-data-dir，而不是浏览器 IndexedDB，避免多个目标互相覆盖。
- 若该 flag 初始化失败，code-server 会回退浏览器存储；此时多会话可能共享状态，需在日志/UI 提示。
- Service Worker 仍按 origin 共享：**所有会话固定同一 code-server 版本**，避免不同版本 SW 冲突。
- localStorage 可能仍有少量共享键；功能不受影响，作为已知限制。

### 5.3 生命周期与租约

1. 打开 IDE：预检 → 安装（如需）→ 启动 → 健康检查 → attachLease(connectionId, ide:<sessionId>) → 返回 URL。
2. 运行中：代理请求 touch(connectionId)；WS 连接计入活动；租约防止 SSH 空闲回收。
3. 关闭窗口/点击停止：SIGTERM（kill -TERM pid）→ 等待 → SIGKILL；关闭 bridge 监听；detachLease；删除远端 session 文件。
4. SSH 断开：关闭 bridge；尽力 kill 远端进程（若连接已断则依赖 --idle-timeout-seconds=1800 自退）；标记会话 stopped。
5. HostDeck 重启：启动时清扫本地残留 bridge；对远端 session 文件做 /healthz 探测，选择接管或清理。
6. HostDeck 退出：best-effort 停止所有会话；来不及则依赖远端 idle timeout。
7. 禁止把 --auth none 的端口暴露到 0.0.0.0；所有监听仅 127.0.0.1。

## 6. API 与数据

text
GET    /api/code-server/packages               离线包列表
POST   /api/code-server/packages               上传（multipart，流式）
DELETE /api/code-server/packages/<id>          删除
POST   /api/code-server/packages/scan         扫描离线目录
GET    /api/code-server/targets/<connectionId>/status   预检/安装/会话状态
POST   /api/code-server/targets/<connectionId>/install  安装指定包
POST   /api/code-server/targets/<connectionId>/start    启动（folder）
POST   /api/code-server/targets/<connectionId>/stop     停止
GET    /api/code-server/targets/<connectionId>/events   SSE 进度
GET    /ide/<sessionId>/...                    代理（自行鉴权，非 /api）

- 普通接口继续用 Result.ok/fail；SSE 参考 runtime sessions stream；上传/下载走非统一响应。
- 数据库：新增 code_server_packages、code_server_sessions 表，schema 版本 +1（当前 v21）。
- 配置：默认版本、最大会话数、空闲超时、离线目录、允许上传大小；CLI 提供 --code-server-offline-dir 等。

## 7. 安全

- /ide 每个请求都走 AccessAuthService.authenticate；WS 额外校验 Origin 与 Host 同源。
- 不把 HostDeck Cookie/Authorization 转发给 code-server。
- code-server 仅 loopback；远端多用户主机上，同机其他用户理论上可访问该 loopback 端口（--auth none 的已知风险）。
  - 默认：文档标注「建议单用户/受信主机」。
  - 加固（P2 可选）：每会话随机密码 + 代理端完成登录并注入会话 Cookie；或改用 --socket + SSH streamlocal（需额外桥接实现）。
- 会话 ID 随机、不可枚举；代理只允许访问注册表中的会话，不接受任意 URL（避免 SSRF）。
- 离线包 sha256 校验；上传大小限制；防止 tar 路径穿越（解压前检查包内路径或使用受控目录）。

## 8. 异常与恢复

| 场景 | 处理 |
| --- | --- |
| 远端无包/架构不匹配 | 阻止安装，提示上传对应 arch 包 |
| 传输中断 | 标记失败、清理 .partial、可重试；SFTP 方案支持续传 |
| 端口占用 | 递增重试；记录日志 |
| 启动后 healthz 失败 | 抓取远端日志尾部，返回明确错误（glibc/端口/noexec） |
| SSH 断开 | 关闭 bridge/租约；远端 idle timeout 兜底 |
| HostDeck 重启 | 依据远端 session 文件 + healthz 接管/清理 |
| 多会话版本不一致 | 阻止混用，提示统一版本 |
| 代理上游 5xx/超时 | 透传状态码；超时中断上游；前端显示重试 |

## 9. 任务拆分与估算

| 阶段 | 任务 | 人日 |
| --- | --- | --- |
| P1 代理内核 | /ide 分流 + 鉴权 + 剥离前缀 + HTTP/WS + 超时/日志 + 单测 | 4～6 |
| P2 离线包 | 包格式/清单、上传/校验/缓存/列表/删除、扫描目录 | 3～4 |
| P3 远端安装 | 预检、SFTP 或 execStream 传输、解压、校验、升级/回滚、SSE | 5～7 |
| P4 会话 | 启动/停止/健康、端口、租约、bridge、恢复、上限 | 4～5 |
| P5 前端 | IDE 窗口、安装/启动/错误 UI、包管理页、多会话入口 | 3～4 |
| P6 硬化 | 安全测试、性能压测、Docker/文档、发布资产 | 4～6 |
| 合计 |  | **23～32 人日** |

可先交付的 MVP：P1 + P2 + P3 + P4 的最小闭环（单会话）约 15～20 人日；再加多会话与包管理 UI。

## 10. 验收标准

- 目标机无外网、未装 code-server，上传离线包后可完成安装并打开 IDE。
- 同一 HostDeck 同时连两台 Linux 主机，两个 IDE 窗口并行可用，状态互不覆盖。
- 未登录访问 /ide/... 返回 401；跨站 WS 被拒；任意未注册 sessionId 404。
- 关闭窗口后远端进程退出、端口释放；SSH 断开后无孤儿进程（或 idle timeout 生效）。
- HostDeck 重启后可接管或清理远端会话，不重复下载/安装。
- 扩展安装、内置终端、文件保存、搜索可用；首屏在局域网的 SSH 链路上 ≤ 5s。
- 退出 HostDeck 后无本地 bridge 端口和远端 code-server 残留。

## 11. 仍需确认

1. 远端多用户主机是否必须防同机其他用户访问 IDE？若是，P2 需加随机密码/Unix socket 方案。
2. 最大并发会话数（默认 4）与单目标内存告警阈值。
3. 离线包是否需要签名（除 sha256 外）与自动更新策略。
4. code-server 版本策略：全局固定一个版本，还是允许按目标机选择（影响 Service Worker 冲突风险）。
5. 是否需要 VSIX 离线安装（完全无外网时的扩展安装）。

## 12. 实现状态（2026-10-29）

已完成 MVP（可运行、已用真实 sshd 验证）：

- 后端：代理中间件、会话管理、离线包存储、SSH 预检/SFTP 安装/启动/停止、SSH bridge、API、容器/路由装配。
- 前端：CodeServerView、API 客户端、应用注册/图标、Vite /ide 代理、离线包上传/删除/扫描、状态轮询、iframe。
- 测试：proxy 6 项、package store 14 项、remote provider 20 项；全仓库 341 项测试通过；flutter analyze 零告警；前端 build + vue-tsc 通过。
- 真实链路：本地 sshd + 219MB 离线包，上传 4.4s、远端安装 17s、启动 1.9s；/ide/ HTML 200、workbench.js 5.4MB 200、/healthz 正常、带 Cookie 的 WebSocket 升级成功；stop 后进程/端口/bridge 清理完成。

未完成（见 docs/modules/code-server.md「已知限制」）：重启接管、SSE 进度、VSIX 离线安装、版本切换 UI、CLI 配置、共享主机强隔离。

- 展示方式调整：运行窗口内嵌 iframe 加载 IDE，同时保留新标签页打开按钮（代理与鉴权不变）。
