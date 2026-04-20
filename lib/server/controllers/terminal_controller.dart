import 'dart:convert';
import 'dart:typed_data';
import 'package:shelf/shelf.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../services/ssh_service.dart';
import '../models/ssh_session.dart';
import '../models/result.dart';

class TerminalController {
  final SshService _sshService;

  TerminalController(this._sshService);

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
      })(request);
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

      final session = await _sshService.createShell(connectionId);

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

  void _attachSession(WebSocketChannel channel, SshSession session) {
    final shell = session.shell;
    if (shell == null) {
      channel.sink.close(1011, 'Shell not available');
      return;
    }

    // Forward SSH output to WS
    final sub = session.output.listen(
      (data) {
        channel.sink.add(data);
      },
      onDone: () {
        channel.sink.close();
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
      },
    );
  }
}
