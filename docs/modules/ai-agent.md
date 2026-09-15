# AI 运维 Agent

AI 运维 Agent 是独立于 Agent CLI 的后端功能，代码位于 `lib/server/features/ai_agent/`，路由前缀为 `/api/ai-agent`。模型接入使用 LangChain.dart 的 `ChatOpenAI`，支持 OpenAI 兼容 API。

## 设置

- `GET /api/ai-agent/settings`：返回 `baseUrl`、`model`、`hasApiKey`。
- `PUT /api/ai-agent/settings`：可选更新 `baseUrl`、`model`、`apiKey`；空或省略的 `apiKey` 保留当前密钥，`clearApiKey: true` 显式删除。
- `POST /api/ai-agent/settings/test`：使用当前设置以及请求中提供的临时覆盖值发起最小模型请求，不保存覆盖值。临时更换 `baseUrl` 时必须同时提供 API Key，防止已保存密钥被发送到其他端点。

API 密钥不会通过 API 或日志返回。密钥使用安装本地随机 32 字节密钥和 AES-256-GCM 加密后存入 SQLite；本地密钥文件为数据目录下的 `ai_agent.key`，Unix 权限设置为 `0600`。删除此文件后，已有密文无法恢复。

`baseUrl` 支持 HTTP 和 HTTPS，以兼容局域网及自建模型服务。HTTP 不提供传输加密，API Key、提示词和工具结果可能被链路上的其他设备读取，只应在可信网络中使用。

## 会话

- `GET /api/ai-agent/conversations?connectionId=...&limit=...&offset=...`
- `POST /api/ai-agent/conversations`，JSON 为 `{ "connectionId": "..." }`
- `GET /api/ai-agent/conversations/<id>?connectionId=...`
- `DELETE /api/ai-agent/conversations/<id>?connectionId=...`
- `POST /api/ai-agent/conversations/<id>/runs`，JSON 为 `{ "connectionId": "...", "input": "..." }`

会话绑定服务端从 SSH 连接元数据计算的稳定目标：已保存服务器使用 `server:<id>`，临时连接使用 `username@host:port`。客户端提供的目标身份不会被信任。同一会话只允许一个活动 run，历史最多向模型加载最近 100 条消息。

## 审批与取消

系统状态是自动只读工具。进程列表、任意 shell 命令、远端文件读取、文件写入和 patch 都必须等待审批；进程命令行和文件内容可能包含敏感信息，因此不会在未确认时发送给模型。

- `POST /api/ai-agent/runs/<id>/approve`，JSON 为 `{ "callId": "..." }`
- `POST /api/ai-agent/runs/<id>/reject`，JSON 为 `{ "callId": "..." }`
- `DELETE /api/ai-agent/runs/<id>`：取消 run。

审批只匹配当前 run 内不可变的精确 `callId` 和参数，五分钟后过期。拒绝会作为工具结果返回模型，取消或 SSH 断开会解除待审批并阻止后续工具执行。工具循环最多执行 8 轮；工具输出上限为 64 KiB，单次工具通常在 60 秒超时。

## SSE

run 接口返回 `text/event-stream`，并发送代理刷新 padding。事件包括：

- `connected`：`{runId}`
- `message-delta`：`{messageId,text}`
- `tool-start`：`{callId,name,summary}`
- `approval-required`：`{callId,name,summary,arguments}`
- `tool-result`：`{callId,name,success,summary}`
- `usage`：可选 token 使用量
- `done`：`{conversationId,messageId}`
- `error`：`{message}`

当前模型调用按完整消息返回，因此 MVP 会在单个 `message-delta` 中发送最终文本；事件结构允许前端按增量方式消费。

## 审计边界

设置、会话 mutation、run、审批、拒绝和取消由操作日志中间件记录。每次工具执行额外记录 `aiAgent` 分类以及稳定目标身份。提示词、模型输出、命令和命令输出、文件路径和内容、patch、API 密钥不会写入操作日志。
