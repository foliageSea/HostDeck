# Agent MCP

Agent MCP 把 HostDeck 的 Agent API 包装成 stdio MCP（Model Context Protocol）服务，供 Claude Code、Codex、OpenCode 等本地 Agent 直接挂载调用。MCP 服务本身不持有 SSH 凭据，只调用本机已运行的 HostDeck HTTP API；SSH 连接、限流和操作日志仍由 HostDeck 服务端管理。

## 代码入口

- `bin/hostdeck_mcp.dart`：MCP 服务入口（参数解析、stdio 循环）
- `lib/agent/hostdeck_mcp_server.dart`：JSON-RPC 2.0 协议处理与工具定义
- `lib/agent/hostdeck_agent_client.dart`：与 `bin/hostdeck_cli.dart` 共享的 HostDeck Agent API 客户端（服务发现、鉴权、请求/响应处理）
- `lib/server/features/agent/agent_controller.dart`：服务端 Agent API

## 协议

- 传输：stdio，newline-delimited JSON-RPC 2.0（每行一条消息）
- 协议版本：`2025-06-18`
- 支持方法：`initialize`、`ping`、`tools/list`、`tools/call`；通知（无 `id`）不应答
- stdout 只输出协议消息，诊断信息一律写 stderr

## 工具

| 工具 | 说明 | 必填参数 | 可选参数 |
| --- | --- | --- | --- |
| `hostdeck_discover` | 解析并探测 HostDeck 服务地址 | - | - |
| `hostdeck_sessions` | 列出 SSH 连接/会话 | - | - |
| `hostdeck_exec` | 执行远端命令 | `connectionId`、`command` | `cwd`、`timeoutMs`、`maxOutputBytes` |
| `hostdeck_read_file` | 读远端文本文件 | `connectionId`、`path` | - |
| `hostdeck_write_file` | 写远端文本文件 | `connectionId`、`path`、`content` | - |
| `hostdeck_apply_patch` | 远端应用 unified diff | `connectionId`、`patch` | `cwd`、`timeoutMs` |

工具结果是 MCP content 数组，文本内容为 HostDeck 的 Result JSON：`{"code": int, "message": string, "data": ...}`；当 `code != 200` 或本地调用失败时 `isError = true`。

## 用法

```bash
hostdeck_mcp [--hostdeck-url <url>] [--token <token>]
```

- 服务地址优先级：`--hostdeck-url` > `HOSTDECK_URL` > `~/.config/host-deck/instance.json` > `http://127.0.0.1:8080`
- 认证：`--token` 或 `HOSTDECK_TOKEN`，以 Bearer 头透传给 HostDeck 服务
- `HOSTDECK_DISCOVERY_FILE` 可覆盖实例文件路径

MCP 客户端配置示例（如 `.mcp.json`）：

```json
{
  "mcpServers": {
    "hostdeck": {
      "command": "hostdeck_mcp",
      "env": { "HOSTDECK_TOKEN": "<token-if-needed>" }
    }
  }
}
```

也可以直接用 `dart run` 挂载：

```json
{
  "mcpServers": {
    "hostdeck": {
      "command": "dart",
      "args": ["run", "bin/hostdeck_mcp.dart"],
      "cwd": "<HostDeck 仓库路径>"
    }
  }
}
```

## 编译

```bash
./scripts/build_hostdeck_mcp.sh
```

默认构建结果位于 `build/hostdeck-mcp/`，可用 `--output <dir>` 覆盖输出目录。

## 约束

- HostDeck 服务必须已经启动；MCP 服务每次工具调用都会按优先级重新解析服务地址，因此 HostDeck 重启换端口后无需重启 MCP。
- `hostdeck_exec` 需检查 `data.exitCode` 判断远端命令是否成功，并检查 `data.truncated` 判断 stdout/stderr 是否被截断。
- `hostdeck_apply_patch` 依赖远端工作目录是 Git 仓库且安装了 `git`，先执行 `git apply --check -` 再执行 `git apply -`。
- 命令执行默认超时 60000ms；exec 默认限制 stdout/stderr 各 524288 字节。
- 工具参数校验失败（如缺少 `connectionId`）会以 `isError = true`、`code = 400` 的工具结果返回，不会触发 JSON-RPC 错误。
