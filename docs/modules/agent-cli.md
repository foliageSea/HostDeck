# Agent CLI

Agent CLI 用于让本地 OpenCode 通过 HostDeck 服务维护远端服务器。CLI 本身不直接持有 SSH 凭据，只调用本机 HostDeck HTTP API；SSH 连接、限流和操作日志仍由服务端管理。

## 代码入口

- `bin/hostdeck_cli.dart`
- `lib/server/features/agent/agent_controller.dart`
- `lib/server/features/agent/agent_service.dart`
- `lib/server/routes/agent_routes.dart`

## API

- `GET /api/agent/sessions`：获取当前 HostDeck 维护的 SSH 连接和 session 列表。
- `POST /api/agent/exec`：执行远端命令，返回 `exitCode`、`stdout`、`stderr`、`durationMs`。
- `POST /api/agent/file/read`：读取远端文本文件。
- `POST /api/agent/file/write`：写入远端文本文件。
- `POST /api/agent/patch`：在远端目录执行 `git apply --check -`，通过后再 `git apply -`。

## CLI 用法

```bash
hostdeck sessions --hostdeck-url http://127.0.0.1:8081
hostdeck exec --connection <id> --cwd /var/www/app -- git status --short
hostdeck read --connection <id> --path /var/www/app/package.json
hostdeck write --connection <id> --path /tmp/demo.txt --file local.txt
hostdeck patch --connection <id> --cwd /var/www/app --file fix.diff
```

也可以从 stdin 传入文件内容或 patch：

```bash
hostdeck patch --connection <id> --cwd /var/www/app < fix.diff
```

## 编译

```bash
fvm dart build cli --target bin/hostdeck_cli.dart --output build/hostdeck-cli
```

## 约束

- 默认 HostDeck 服务地址是 `http://127.0.0.1:8080`，可用 `--hostdeck-url` 覆盖。
- 命令执行默认超时 60000ms。
- `exec` 默认限制 stdout/stderr 各 524288 字节。
- `patch` 依赖远端工作目录是 Git 仓库，并且远端安装了 `git`。
