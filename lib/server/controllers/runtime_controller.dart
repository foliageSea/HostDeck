import 'dart:async';
import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/result.dart';
import '../services/ssh_service.dart';

class RuntimeController {
  final SshService _sshService;

  RuntimeController(this._sshService);

  Future<Response> listSessions(Request request) async {
    try {
      return Result.ok(_sshService.getRuntimeSnapshot());
    } catch (e) {
      return Result.fail(500, e.toString());
    }
  }

  Handler get wsSessions {
    return (Request request) {
      return webSocketHandler((WebSocketChannel channel, String? protocol) {
        Timer? timer;
        var isActive = true;

        void sendSnapshot() {
          if (!isActive) {
            return;
          }

          try {
            channel.sink.add(
              jsonEncode({
                'code': 200,
                'data': _sshService.getRuntimeSnapshot(),
                'message': 'success',
              }),
            );
          } catch (e) {
            channel.sink.add(
              jsonEncode({'code': 500, 'data': null, 'message': e.toString()}),
            );
          }
        }

        void dispose() {
          isActive = false;
          timer?.cancel();
          timer = null;
        }

        sendSnapshot();
        timer = Timer.periodic(const Duration(seconds: 3), (_) {
          sendSnapshot();
        });

        channel.stream.listen(
          (message) {
            if (message == 'ping') {
              channel.sink.add('pong');
              return;
            }

            if (message == 'refresh') {
              sendSnapshot();
            }
          },
          onDone: dispose,
          onError: (_) {
            dispose();
          },
        );
      })(request);
    };
  }
}
