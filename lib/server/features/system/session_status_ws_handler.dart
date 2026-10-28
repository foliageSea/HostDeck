import 'dart:async';
import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:host_deck/server/core/ssh/ssh_service.dart';

/// 浏览器页面存活探针。
///
/// 这个 WebSocket 只回答「页面还在不在」，不再直接决定 SSH 连接的死活：
/// 心跳超时或 WS 关闭时只释放租约，整条连接交给 [SshService] 的空闲回收器
/// （无租约 + 超过 channelIdleGrace 没有可见活动）统一处理。这样一次 WS
/// 抖动不会把终端、文件、Docker、AI Agent 会话一起拆掉。
class SessionStatusWsHandler {
  static const _heartbeatTimeout = Duration(seconds: 30);
  static int _channelSequence = 0;

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

        final client = _sshService.getClient(connectionId);
        if (client == null) {
          channel.sink.close(4004, 'Connection not found');
          return;
        }

        final leaseId = 'status-ws-${_channelSequence++}';
        _sshService.attachLease(connectionId, leaseId);

        Timer? heartbeatTimer;
        var isCleanedUp = false;

        void cleanup(String reason) {
          if (isCleanedUp) {
            return;
          }

          isCleanedUp = true;
          heartbeatTimer?.cancel();
          heartbeatTimer = null;
          _sshService.detachLease(connectionId, leaseId);
          _log.fine(
            'Session status WS closed for $connectionId ($reason); lease '
            'released, SSH idle grace '
            '${SshService.channelIdleGrace.inSeconds}s',
          );
        }

        void resetHeartbeatTimeout() {
          heartbeatTimer?.cancel();
          heartbeatTimer = Timer(_heartbeatTimeout, () async {
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

              cleanup('client done');
            })
            .catchError((e) {
              if (!isCleanedUp) {
                channel.sink.close(1011, 'SSH Connection Error');
              }

              cleanup('client error');
            });

        channel.stream.listen(
          (message) {
            if (message == 'ping') {
              _sshService.touch(connectionId);
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
