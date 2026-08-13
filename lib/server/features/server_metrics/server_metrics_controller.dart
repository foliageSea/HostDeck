import 'dart:async';
import 'dart:convert';

import 'package:shelf/shelf.dart';

import 'package:host_deck/server/core/http/server_sent_event.dart';
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

  Response stream(Request request) {
    return Response.ok(
      _encodeSnapshots(),
      headers: const {
        'content-type': 'text/event-stream; charset=utf-8',
        'cache-control': 'no-cache, no-transform',
        'connection': 'keep-alive',
        'x-accel-buffering': 'no',
      },
      context: const {'shelf.io.buffer_output': false},
    );
  }

  Stream<List<int>> _encodeSnapshots() async* {
    yield <int>[
      ...utf8.encode(': ${' '.padRight(2048)}\n\n'),
      ...encodeServerSentEvent('connected', const {}, retry: 3000),
    ];
    try {
      await for (final snapshot in _metricsService.watchSnapshots()) {
        yield encodeServerSentEvent('metrics', snapshot.toJson());
      }
    } catch (error) {
      yield encodeServerSentEvent('error', {'message': error.toString()});
    }
  }
}
