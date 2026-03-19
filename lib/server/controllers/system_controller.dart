import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../services/ssh_service.dart';
import '../services/monitor_service.dart';
import '../models/result.dart';

class SystemController {
  final SshService _sshService;
  final MonitorService _monitorService;

  SystemController(this._sshService, this._monitorService);

  Response status(Request request) {
    return Result.ok({'status': 'running'});
  }

  Handler get wsSessionStatus {
    return (Request request) {
      final sessionId = request.url.queryParameters['sessionId'];
      return webSocketHandler((WebSocketChannel channel, String? protocol) {
        if (sessionId == null) {
          channel.sink.close(4000, 'Missing sessionId parameter');
          return;
        }

        final session = _sshService.getSession(sessionId);
        if (session == null) {
          channel.sink.close(4004, 'Session not found');
          return;
        }

        // Monitor the actual SSH client connection
        session.client.done.then((_) {
          channel.sink.add(jsonEncode({'type': 'status', 'status': 'disconnected'}));
          channel.sink.close(1011, 'SSH Connection Lost');
        }).catchError((e) {
          channel.sink.close(1011, 'SSH Connection Error');
        });

        channel.stream.listen(
          (message) {
            if (message == 'ping') {
              channel.sink.add('pong');
            }
          },
          onDone: () {},
          onError: (e) {}
        );
      })(request);
    };
  }

  Handler get wsMonitor {
    return (Request request) {
      final sessionId = request.url.queryParameters['sessionId'];
      return webSocketHandler((WebSocketChannel channel, String? protocol) {
        if (sessionId == null) {
          channel.sink.close(4000, 'Missing sessionId parameter');
          return;
        }

        final session = _sshService.getSession(sessionId);
        if (session == null) {
          channel.sink.close(4004, 'Session not found');
          return;
        }

        bool isMonitoring = true;

        void startMonitoring() async {
          while (isMonitoring && !session.client.isClosed) {
            try {
              final status = await _monitorService.getSystemStatus(session);
              if (isMonitoring) {
                 channel.sink.add(jsonEncode({
                   'code': 200,
                   'data': status.toJson(),
                   'message': 'success'
                 }));
              }
            } catch (e) {
               if (isMonitoring) {
                  channel.sink.add(jsonEncode({
                    'code': 500,
                    'message': e.toString(),
                    'data': null
                  }));
                  
                  final errorStr = e.toString();
                  if (errorStr.contains('SocketException') || 
                      errorStr.contains('SSHChannelOpenError') ||
                      session.client.isClosed) {
                    channel.sink.close(1011, 'SSH Connection Lost');
                    isMonitoring = false;
                    break;
                  }
               }
            }
            
            if (isMonitoring) {
               await Future.delayed(const Duration(seconds: 3));
            }
          }
          
          if (isMonitoring && session.client.isClosed) {
             channel.sink.close(1011, 'SSH Connection Lost');
          }
        }

        startMonitoring();

        channel.stream.listen(
          (message) {}, // Ignore incoming messages
          onDone: () {
            isMonitoring = false;
          },
          onError: (e) {
            isMonitoring = false;
          }
        );
      })(request);
    };
  }
}
