import 'dart:async';
import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../services/ssh_service.dart';

class SessionStatusWsHandler {
  final _log = Logger('SessionStatusWsHandler');
  final SshService _sshService;

  SessionStatusWsHandler(this._sshService);

  Handler get handler {
    return (Request request) {
      final connectionId = request.url.queryParameters['connectionId'];
      return webSocketHandler((WebSocketChannel channel, String? protocol) {
        if (connectionId == null) {
          channel.sink.close(4000, 'Missing connectionId parameter');
          return;
        }

        final connection = _sshService.getConnectionById(connectionId);
        if (connection == null) {
          channel.sink.close(4004, 'Connection not found');
          return;
        }

        Timer? heartbeatTimer;
        StreamSubscription? subscription;
        var isCleanedUp = false;

        void cleanup(String reason) {
          if (isCleanedUp) {
            return;
          }

          isCleanedUp = true;
          heartbeatTimer?.cancel();
          unawaited(subscription?.cancel());
          _log.fine('Session status WS cleaned up for $connectionId: $reason');
        }

        void resetHeartbeatTimeout() {
          heartbeatTimer?.cancel();
          heartbeatTimer = Timer(const Duration(seconds: 30), () async {
            if (isCleanedUp) {
              return;
            }

            cleanup('heartbeat timeout');
            await channel.sink.close(4008, 'Heartbeat timeout');
          });
        }

        resetHeartbeatTimeout();

        channel.sink.add(
          jsonEncode({'type': 'status', ...connection.toClientJson()}),
        );

        subscription = _sshService.watchConnection(connectionId)?.listen((event) {
          if (isCleanedUp) {
            return;
          }

          channel.sink.add(jsonEncode({'type': 'status', ...event.toClientJson()}));
        });

        channel.stream.listen(
          (message) {
            if (message == 'ping') {
              resetHeartbeatTimeout();
              channel.sink.add('pong');
            }
          },
          onDone: () {
            cleanup('websocket closed');
          },
          onError: (e) {
            cleanup('websocket error');
          },
        );
      })(request);
    };
  }
}
