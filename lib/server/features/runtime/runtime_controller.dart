import 'dart:async';
import 'dart:convert';
import 'package:shelf/shelf.dart';

import 'package:host_deck/server/core/http/result.dart';
import 'package:host_deck/server/core/http/server_sent_event.dart';
import 'package:host_deck/server/core/ssh/ssh_service.dart';

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

  Response streamSessions(Request request) {
    late final StreamController<List<int>> controller;
    Timer? timer;

    void sendSnapshot() {
      if (controller.isClosed) return;

      try {
        controller.add(
          encodeServerSentEvent('snapshot', _sshService.getRuntimeSnapshot()),
        );
      } catch (error) {
        controller.add(
          encodeServerSentEvent('snapshot-error', {
            'message': error.toString(),
          }),
        );
      }
    }

    controller = StreamController<List<int>>(
      onListen: () {
        controller.add(<int>[
          ...utf8.encode(': ${' '.padRight(2048)}\n\n'),
          ...encodeServerSentEvent('connected', const {}, retry: 3000),
        ]);
        sendSnapshot();
        timer = Timer.periodic(
          const Duration(seconds: 3),
          (_) => sendSnapshot(),
        );
      },
      onCancel: () {
        timer?.cancel();
        timer = null;
      },
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
}
