import 'dart:async';
import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:host_deck/server/core/http/result.dart';
import 'package:host_deck/server/features/server_metrics/server_metrics_service.dart';

class ServerMetricsController {
  final ServerMetricsService _metricsService;

  ServerMetricsController(this._metricsService);

  Future<Response> snapshot(Request request) async {
    try {
      return Result.ok((await _metricsService.getSnapshot()).toJson());
    } catch (e) {
      return Result.fail(500, e.toString());
    }
  }

  Handler get wsMetrics {
    return (Request request) {
      return webSocketHandler((WebSocketChannel channel, String? protocol) {
        Timer? timer;
        var isActive = true;
        var isSampling = false;

        Future<void> sendSnapshot() async {
          if (!isActive || isSampling) return;
          isSampling = true;
          try {
            final snapshot = await _metricsService.getSnapshot();
            if (isActive) {
              channel.sink.add(
                jsonEncode({
                  'code': 200,
                  'data': snapshot.toJson(),
                  'message': 'success',
                }),
              );
            }
          } catch (e) {
            if (isActive) {
              channel.sink.add(
                jsonEncode({
                  'code': 500,
                  'data': null,
                  'message': e.toString(),
                }),
              );
            }
          } finally {
            isSampling = false;
          }
        }

        void dispose() {
          isActive = false;
          timer?.cancel();
          timer = null;
        }

        unawaited(sendSnapshot());
        timer = Timer.periodic(
          const Duration(seconds: 3),
          (_) => unawaited(sendSnapshot()),
        );
        channel.stream.listen(
          (message) {
            if (message == 'ping') {
              channel.sink.add('pong');
            } else if (message == 'refresh') {
              unawaited(sendSnapshot());
            }
          },
          onDone: dispose,
          onError: (_) => dispose(),
        );
      })(request);
    };
  }
}
