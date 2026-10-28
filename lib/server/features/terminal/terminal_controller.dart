import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:shelf/shelf.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:host_deck/server/core/http/result.dart';
import 'package:host_deck/server/core/ssh/ssh_service.dart';
import 'package:host_deck/server/core/ssh/ssh_session.dart';
import 'package:host_deck/server/features/terminal/terminal_snippet.dart';
import 'package:host_deck/server/features/terminal/terminal_snippet_repository.dart';

class TerminalController {
  static int _channelSequence = 0;

  final SshService _sshService;
  final TerminalSnippetRepository _snippetRepository;

  TerminalController(this._sshService, this._snippetRepository);

  Handler get handler {
    return (Request request) {
      final sessionId = request.url.queryParameters['sessionId'];
      return webSocketHandler((channel, protocol) {
        if (sessionId != null) {
          final session = _sshService.getSession(sessionId);
          if (session != null) {
            _attachSession(channel, session);
          } else {
            channel.sink.close(4004, 'Session not found');
          }
        } else {
          channel.sink.close(4000, 'Missing sessionId');
        }
      }, pingInterval: const Duration(seconds: 20))(request);
    };
  }

  Future<Response> createSession(Request request) async {
    try {
      final payload = await request.readAsString();
      final data = jsonDecode(payload);
      final connectionId = data['connectionId'];

      if (connectionId == null) {
        return Result.fail(400, 'Missing connectionId');
      }

      final session = await _sshService.createShell(
        connectionId,
        purpose: SshSessionPurpose.terminal,
      );

      return Result.ok({'sessionId': session.id});
    } on SshSessionLimitExceeded catch (e) {
      return Result.fail(429, '最多只能创建 ${e.maxSessions} 个 SSH 会话。');
    } catch (e) {
      return Result.fail(500, e.toString());
    }
  }

  Future<Response> closeSession(Request request) async {
    try {
      final sessionId = request.url.queryParameters['sessionId'];
      if (sessionId == null) {
        return Result.fail(400, 'Missing sessionId');
      }

      await _sshService.closeSession(sessionId);

      return Result.ok('Session closed');
    } catch (e) {
      return Result.fail(500, e.toString());
    }
  }

  Future<Response> listSnippets(Request request) async {
    try {
      return Result.ok(
        _snippetRepository.getAll().map((item) => item.toJson()).toList(),
      );
    } catch (e) {
      return Result.fail(500, e.toString());
    }
  }

  Future<Response> createSnippet(Request request) async {
    try {
      final snippet = TerminalSnippet.fromJson(await _readJson(request));
      return Result.ok(_snippetRepository.add(snippet).toJson());
    } on ArgumentError catch (e) {
      return Result.fail(400, e.message?.toString() ?? '无效的命令片段。');
    } catch (e) {
      return Result.fail(500, e.toString());
    }
  }

  Future<Response> updateSnippet(Request request, String idStr) async {
    final id = int.tryParse(idStr);
    if (id == null) {
      return Result.fail(400, 'Invalid snippet ID');
    }

    try {
      final snippet = TerminalSnippet.fromJson(await _readJson(request));
      final updated = _snippetRepository.update(id, snippet);
      if (updated == null) {
        return Result.fail(404, 'Command snippet not found');
      }
      return Result.ok(updated.toJson());
    } on ArgumentError catch (e) {
      return Result.fail(400, e.message?.toString() ?? '无效的命令片段。');
    } catch (e) {
      return Result.fail(500, e.toString());
    }
  }

  Future<Response> deleteSnippet(Request request, String idStr) async {
    final id = int.tryParse(idStr);
    if (id == null) {
      return Result.fail(400, 'Invalid snippet ID');
    }

    try {
      if (!_snippetRepository.delete(id)) {
        return Result.fail(404, 'Command snippet not found');
      }
      return Result.ok({'success': true});
    } catch (e) {
      return Result.fail(500, e.toString());
    }
  }

  Future<Map<String, dynamic>> _readJson(Request request) async {
    final payload = await request.readAsString();
    if (payload.trim().isEmpty) {
      throw ArgumentError('请求内容不能为空。');
    }
    final data = jsonDecode(payload);
    if (data is! Map<String, dynamic>) {
      throw ArgumentError('无效的请求内容。');
    }
    return data;
  }

  void _attachSession(WebSocketChannel channel, SshSession session) {
    final shell = session.shell;
    if (shell == null) {
      channel.sink.close(1011, 'Shell not available');
      return;
    }

    final leaseId = 'terminal-ws-${_channelSequence++}';
    _sshService.attachLease(session.connectionId, leaseId);
    var isDetached = false;

    Future<void> detach({required bool closeSession}) async {
      if (isDetached) {
        return;
      }

      isDetached = true;
      _sshService.detachLease(session.connectionId, leaseId);
      if (closeSession) {
        // 浏览器已经走了，远端 shell 不能继续挂着。
        await _sshService.closeSession(session.id);
      }
    }

    // Forward SSH output to WS
    final sub = session.output.listen(
      (data) {
        _sshService.touch(session.connectionId);
        try {
          channel.sink.add(data);
        } catch (_) {
          // 通道已经关闭时忽略，统一在 onDone 里收尾。
        }
      },
      onDone: () {
        try {
          channel.sink.close();
        } catch (_) {
          // 已经关闭。
        }
        unawaited(detach(closeSession: false));
      },
    );

    // Forward WS input to SSH
    channel.stream.listen(
      (message) {
        if (message is String) {
          try {
            if (message.startsWith('{')) {
              final data = jsonDecode(message);
              if (data['type'] == 'resize') {
                shell.resizeTerminal(data['cols'], data['rows']);
                return;
              }
            }
          } catch (_) {}

          shell.write(Uint8List.fromList(utf8.encode(message)));
        }
      },
      onDone: () {
        sub.cancel();
        unawaited(detach(closeSession: true));
      },
      onError: (error) {
        sub.cancel();
        unawaited(detach(closeSession: true));
      },
    );
  }
}
