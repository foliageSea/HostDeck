import 'dart:convert';
import 'dart:typed_data';
import 'package:shelf/shelf.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../services/ssh_service.dart';
import '../models/ssh_session.dart';

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

  void _attachSession(WebSocketChannel channel, SshSession session) {
    // Forward SSH output to WS
    final sub = session.output.listen((data) {
      channel.sink.add(data);
    }, onDone: () {
      channel.sink.close();
    });

    // Forward WS input to SSH
    channel.stream.listen((message) {
      if (message is String) {
        try {
           if (message.startsWith('{')) {
              final data = jsonDecode(message);
              if (data['type'] == 'resize') {
                session.shell.resizeTerminal(data['cols'], data['rows']);
                return;
              }
           }
        } catch (_) {}
        
        session.shell.write(Uint8List.fromList(utf8.encode(message)));
      }
    }, onDone: () {
      sub.cancel();
    });
  }
}
