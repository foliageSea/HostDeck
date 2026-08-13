import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:host_deck/server/features/server_metrics/server_metrics_controller.dart';
import 'package:host_deck/server/features/server_metrics/server_metrics_service.dart';
import 'package:shelf/shelf.dart';

void main() {
  test('streams metric snapshots with standard SSE headers', () async {
    final service = ServerMetricsService(
      currentRss: () => 1234,
      maxRss: () => 5678,
      enableLinuxCpu: false,
    );
    addTearDown(service.dispose);
    final controller = ServerMetricsController(service);

    final response = controller.stream(
      Request('GET', Uri.parse('http://localhost/api/server/metrics/stream')),
    );

    expect(response.statusCode, 200);
    expect(
      response.headers['content-type'],
      'text/event-stream; charset=utf-8',
    );
    expect(response.headers['cache-control'], 'no-cache, no-transform');
    expect(response.headers['connection'], 'keep-alive');
    expect(response.headers['x-accel-buffering'], 'no');
    expect(response.context['shelf.io.buffer_output'], isFalse);

    final iterator = StreamIterator<List<int>>(response.read());
    expect(await iterator.moveNext(), isTrue);
    final connected = utf8.decode(iterator.current);
    expect(connected, startsWith(': '));
    expect(connected, endsWith('event: connected\nretry: 3000\ndata: {}\n\n'));

    expect(await iterator.moveNext(), isTrue);
    final metrics = utf8.decode(iterator.current);
    expect(metrics, startsWith('event: metrics\n'));
    expect(metrics, contains('"rssBytes":1234'));
    expect(metrics, contains('"peakRssBytes":5678'));

    await iterator.cancel();
  });
}
