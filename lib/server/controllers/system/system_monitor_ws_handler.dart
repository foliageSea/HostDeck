import 'dart:async';
import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../models/ssh_session.dart';
import '../../services/monitor_service.dart';
import '../../services/ssh_service.dart';

class SystemMonitorWsHandler {
  final SshService _sshService;
  final MonitorService _monitorService;

  SystemMonitorWsHandler(this._sshService, this._monitorService);

  Handler get handler {
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

        Future<void> closeMonitorSession() async {
          final session = monitorSession;
          if (session == null) {
            return;
          }

          monitorSession = null;
          _monitorService.clearSession(session.id);
          await _sshService.closeSession(session.id);
        }

        bool isConnectionLostError(Object error) {
          final errorStr = error.toString();
          return client.isClosed ||
              errorStr.contains('SocketException') ||
              errorStr.contains('Connection is closed') ||
              errorStr.contains('Connection not found');
        }

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
          try {
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

                  if (isConnectionLostError(e)) {
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
          } finally {
            await closeMonitorSession();
          }
        }

        startMonitoring();

        channel.stream.listen(
          (message) {}, // Ignore incoming messages
          onDone: () {
            isMonitoring = false;
            unawaited(closeMonitorSession());
          },
          onError: (e) {
            isMonitoring = false;
            unawaited(closeMonitorSession());
          },
        );
      })(request);
    };
  }
}
