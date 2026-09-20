import 'dart:io';

import 'package:host_deck/agent/hostdeck_agent_client.dart';
import 'package:host_deck/agent/hostdeck_mcp_server.dart';

Future<void> main(List<String> args) async {
  if (args.contains('--help') || args.contains('-h')) {
    _printUsage();
    return;
  }

  final options = _parseArgs(args);
  final token = options['token'] ?? HostDeckAgentClient.tokenFromEnvironment();

  final server = HostDeckMcpServer(
    client: HostDeckAgentClient(baseUrl: options['hostdeck-url'], token: token),
  );

  // MCP runs over stdio; keep stdout protocol-clean and log to stderr only.
  stderr.writeln(
    '${HostDeckMcpServer.serverName} ${HostDeckMcpServer.serverVersion} '
    'listening on stdio (protocol ${HostDeckMcpServer.protocolVersion})',
  );
  await server.run();
}

Map<String, String> _parseArgs(List<String> args) {
  final options = <String, String>{};
  for (var i = 0; i < args.length; i++) {
    final token = args[i];
    if (!token.startsWith('--')) {
      stderr.writeln('Ignoring unexpected argument: $token');
      continue;
    }
    final key = token.substring(2);
    if (i + 1 >= args.length || args[i + 1].startsWith('--')) {
      stderr.writeln('Ignoring option without value: --$key');
      continue;
    }
    options[key] = args[i + 1];
    i++;
  }
  return options;
}

void _printUsage() {
  stdout.writeln('''
HostDeck MCP Server

Exposes the HostDeck agent API as MCP tools over stdio (newline-delimited
JSON-RPC 2.0, protocol ${HostDeckMcpServer.protocolVersion}) so local agents
(Claude Code, Codex, OpenCode, ...) can operate remote servers through an
already running HostDeck instance.

Usage:
  hostdeck_mcp [--hostdeck-url <url>] [--token <token>]

Options:
  --hostdeck-url <url>   HostDeck server URL. Discovery order when omitted:
                         HOSTDECK_URL > ~/.config/host-deck/instance.json >
                         http://127.0.0.1:8080
  --token <token>        API token, or use HOSTDECK_TOKEN

Tools:
  hostdeck_discover      Resolve and probe the HostDeck server endpoint.
  hostdeck_sessions      List SSH connections/sessions (find connectionId).
  hostdeck_exec          Execute a remote command (check data.exitCode and
                         data.truncated in the result).
  hostdeck_read_file     Read a remote UTF-8 text file.
  hostdeck_write_file    Write a remote UTF-8 text file.
  hostdeck_apply_patch   git apply --check then git apply a unified diff in
                         a remote git repository.

Agent contract:
  - All output is JSON-RPC on stdout; diagnostics go to stderr.
  - Tool results wrap the HostDeck Result JSON: {"code": int, "message": str,
    "data": ...}; isError is true when code != 200.
  - HostDeck server must already be running; SSH credentials, rate limits
    and operation logs stay managed by the HostDeck server.

MCP client configuration example (e.g. .mcp.json):
  {
    "mcpServers": {
      "hostdeck": {
        "command": "hostdeck_mcp",
        "env": { "HOSTDECK_TOKEN": "<token-if-needed>" }
      }
    }
  }

Build:
  fvm dart build cli --target bin/hostdeck_mcp.dart --output build/hostdeck-mcp
''');
}
