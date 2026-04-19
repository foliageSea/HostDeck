import 'dart:async';
import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/ssh_session.dart';
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
      final connectionId = request.url.queryParameters['connectionId'];
      return webSocketHandler((WebSocketChannel channel, String? protocol) {
        if (connectionId == null) {
          channel.sink.close(4000, 'Missing connectionId parameter');
          return;
        }

        final client = _sshService.getClient(connectionId);
        if (client == null) {
          channel.sink.close(4004, 'Connection not found');
          return;
        }

        Timer? heartbeatTimer;
        var isCleanedUp = false;

        Future<void> cleanup() async {
          if (isCleanedUp) {
            return;
          }

          isCleanedUp = true;
          heartbeatTimer?.cancel();
          await _sshService.disconnect(connectionId);
        }

        void resetHeartbeatTimeout() {
          heartbeatTimer?.cancel();
          heartbeatTimer = Timer(const Duration(seconds: 30), () async {
            if (isCleanedUp) {
              return;
            }

            await cleanup();
          });
        }

        resetHeartbeatTimeout();

        client.done
            .then((_) {
              if (!isCleanedUp) {
                channel.sink.add(
                  jsonEncode({'type': 'status', 'status': 'disconnected'}),
                );
                channel.sink.close(1011, 'SSH Connection Lost');
              }

              return cleanup();
            })
            .catchError((e) {
              if (!isCleanedUp) {
                channel.sink.close(1011, 'SSH Connection Error');
              }

              return cleanup();
            });

        channel.stream.listen(
          (message) {
            if (message == 'ping') {
              resetHeartbeatTimeout();
              channel.sink.add('pong');
            }
          },
          onDone: () {
            cleanup();
          },
          onError: (e) {
            cleanup();
          },
        );
      })(request);
    };
  }

  Handler get wsMonitor {
    return (Request request) {
      final connectionId = request.url.queryParameters['connectionId'];
      return webSocketHandler((WebSocketChannel channel, String? protocol) {
        if (connectionId == null) {
          channel.sink.close(4000, 'Missing connectionId parameter');
          return;
        }

        final client = _sshService.getClient(connectionId);
        if (client == null) {
          channel.sink.close(4004, 'Connection not found');
          return;
        }

        bool isMonitoring = true;
        SshSession? monitorSession;

        Future<SshSession> resolveMonitorSession() async {
          final existingSession = monitorSession;
          if (existingSession != null) {
            return existingSession;
          }

          final nextSession = await _sshService.createSftpSession(connectionId);
          monitorSession = nextSession;
          return nextSession;
        }

        void startMonitoring() async {
          while (isMonitoring && !client.isClosed) {
            try {
              final session = await resolveMonitorSession();
              final status = await _monitorService.getSystemStatus(session);
              if (isMonitoring) {
                channel.sink.add(
                  jsonEncode({
                    'code': 200,
                    'data': status.toJson(),
                    'message': 'success',
                  }),
                );
              }
            } catch (e) {
              if (isMonitoring) {
                channel.sink.add(
                  jsonEncode({
                    'code': 500,
                    'message': e.toString(),
                    'data': null,
                  }),
                );

                final errorStr = e.toString();
                if (errorStr.contains('SocketException') ||
                    errorStr.contains('SSHChannelOpenError') ||
                    client.isClosed) {
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

          if (isMonitoring && client.isClosed) {
            channel.sink.close(1011, 'SSH Connection Lost');
          }
        }

        startMonitoring();

        channel.stream.listen(
          (message) {}, // Ignore incoming messages
          onDone: () {
            isMonitoring = false;
            final session = monitorSession;
            if (session != null) {
              monitorSession = null;
              _sshService.closeSession(session.id);
            }
          },
          onError: (e) {
            isMonitoring = false;
            final session = monitorSession;
            if (session != null) {
              monitorSession = null;
              _sshService.closeSession(session.id);
            }
          },
        );
      })(request);
    };
  }
}
