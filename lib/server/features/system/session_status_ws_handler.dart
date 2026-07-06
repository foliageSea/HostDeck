import 'dart:async';
import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:host_deck/server/core/ssh/ssh_service.dart';

class SessionStatusWsHandler {
  static const _disconnectDelay = Duration(minutes: 2);

  final _log = Logger('SessionStatusWsHandler');
  final SshService _sshService;
  final Map<String, Timer> _disconnectTimers = {};
  final Map<String, int> _listenerCounts = {};

  SessionStatusWsHandler(this._sshService);

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

        Timer? heartbeatTimer;
        var isCleanedUp = false;
        _registerListener(connectionId);

        void cleanup(String reason, {bool scheduleDisconnect = true}) {
          if (isCleanedUp) {
            return;
          }

          isCleanedUp = true;
          heartbeatTimer?.cancel();
          _unregisterListener(connectionId);
          if (scheduleDisconnect) {
            _scheduleDisconnect(connectionId, reason);
          }
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

        client.done
            .then((_) {
              if (!isCleanedUp) {
                channel.sink.add(
                  jsonEncode({'type': 'status', 'status': 'disconnected'}),
                );
                channel.sink.close(1011, 'SSH Connection Lost');
              }

              cleanup('client done', scheduleDisconnect: false);
            })
            .catchError((e) {
              if (!isCleanedUp) {
                channel.sink.close(1011, 'SSH Connection Error');
              }

              cleanup('client error', scheduleDisconnect: false);
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

  void _registerListener(String connectionId) {
    _cancelPendingDisconnect(connectionId);
    _listenerCounts.update(
      connectionId,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
  }

  void _unregisterListener(String connectionId) {
    final count = _listenerCounts[connectionId];
    if (count == null) {
      return;
    }

    if (count <= 1) {
      _listenerCounts.remove(connectionId);
      return;
    }

    _listenerCounts[connectionId] = count - 1;
  }

  void _cancelPendingDisconnect(String connectionId) {
    final timer = _disconnectTimers.remove(connectionId);
    if (timer == null) {
      return;
    }

    timer.cancel();
    _log.fine('Cancelled pending SSH disconnect for $connectionId');
  }

  void _scheduleDisconnect(String connectionId, String reason) {
    if (_sshService.getClient(connectionId) == null) {
      return;
    }

    if ((_listenerCounts[connectionId] ?? 0) > 0) {
      return;
    }

    _disconnectTimers[connectionId]?.cancel();
    _log.warning(
      'Session status WS closed for $connectionId ($reason); scheduling SSH '
      'disconnect in ${_disconnectDelay.inSeconds}s',
    );

    _disconnectTimers[connectionId] = Timer(_disconnectDelay, () {
      _disconnectTimers.remove(connectionId);
      unawaited(_disconnectInactiveSession(connectionId, reason));
    });
  }

  Future<void> _disconnectInactiveSession(
    String connectionId,
    String reason,
  ) async {
    if ((_listenerCounts[connectionId] ?? 0) > 0) {
      return;
    }

    if (_sshService.getClient(connectionId) == null) {
      return;
    }

    try {
      _log.warning(
        'Disconnecting inactive SSH connection $connectionId after session '
        'status WS closed ($reason)',
      );
      await _sshService.disconnect(connectionId);
    } catch (e, stackTrace) {
      _log.severe(
        'Failed to disconnect inactive SSH connection $connectionId',
        e,
        stackTrace,
      );
    }
  }
}
