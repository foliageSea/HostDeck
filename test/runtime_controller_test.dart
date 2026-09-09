import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:host_deck/server/core/ssh/ssh_service.dart';
import 'package:host_deck/server/features/runtime/runtime_controller.dart';
import 'package:shelf/shelf.dart';

void main() {
  test('streams runtime snapshots with standard SSE headers', () async {
    final controller = RuntimeController(_FakeSshService());

    final response = controller.streamSessions(
      Request('GET', Uri.parse('http://localhost/api/runtime/sessions/stream')),
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
    final snapshot = utf8.decode(iterator.current);
    expect(snapshot, startsWith('event: snapshot\n'));
    expect(snapshot, contains('"totalClients":1'));
    expect(snapshot, contains('"totalSessions":2'));

    await iterator.cancel();
  });
}

class _FakeSshService extends SshService {
  @override
  Map<String, dynamic> getRuntimeSnapshot() => {
    'totalClients': 1,
    'totalSessions': 2,
    'clients': <Map<String, dynamic>>[],
    'sessions': <Map<String, dynamic>>[],
  };
}
