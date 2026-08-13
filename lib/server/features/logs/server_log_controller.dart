import 'dart:async';
import 'dart:convert';

import 'package:shelf/shelf.dart';

import 'package:host_deck/server/core/http/server_sent_event.dart';
import 'package:host_deck/server/features/logs/server_log_service.dart';

class ServerLogController {
  final ServerLogService _service;

  ServerLogController(this._service);

  Response stream(Request request) {
    final requestedCursor = _parseCursor(request);
    final cursor = _service.resolveCursor(requestedCursor);
    late final StreamController<List<int>> controller;
    StreamSubscription<dynamic>? subscription;
    Timer? heartbeat;

    Future<void> cleanup({bool closeController = false}) async {
      heartbeat?.cancel();
      heartbeat = null;
      await subscription?.cancel();
      subscription = null;
      if (closeController && !controller.isClosed) {
        await controller.close();
      }
    }

    controller = StreamController<List<int>>(
      onListen: () {
        final connected = encodeServerSentEvent('connected', {
          'cursor': cursor,
          'requestedCursor': requestedCursor,
          'oldestId': _service.oldestId,
          'latestId': _service.latestId,
          'replayTruncated': _service.isReplayTruncated(requestedCursor),
        }, retry: 3000);
        controller.add(<int>[
          ...utf8.encode(': ${' '.padRight(16 * 1024)}\n\n'),
          ...connected,
        ]);
        subscription = _service
            .subscribe(afterId: cursor)
            .listen(
              (entry) {
                controller.add(
                  encodeServerSentEvent('log', entry.toJson(), id: entry.id),
                );
              },
              onError: (Object error, StackTrace stackTrace) {
                if (!controller.isClosed) {
                  controller.add(
                    encodeServerSentEvent('error', {'message': '实时日志流发生错误。'}),
                  );
                }
                cleanup(closeController: true);
              },
              onDone: () => cleanup(closeController: true),
              cancelOnError: true,
            );
        heartbeat = Timer.periodic(const Duration(seconds: 15), (_) {
          if (!controller.isClosed) {
            controller.add(utf8.encode(': heartbeat\n\n'));
          }
        });
      },
      onCancel: cleanup,
    );

    return Response.ok(
      controller.stream,
      headers: const {
        'content-type': 'text/event-stream; charset=utf-8',
        'cache-control': 'no-cache, no-transform',
        'connection': 'keep-alive',
        'x-accel-buffering': 'no',
      },
      context: const {'shelf.io.buffer_output': false},
    );
  }

  int? _parseCursor(Request request) {
    final raw =
        request.headers['last-event-id'] ??
        request.url.queryParameters['cursor'];
    final value = int.tryParse(raw?.trim() ?? '');
    return value != null && value >= 0 ? value : null;
  }
}
