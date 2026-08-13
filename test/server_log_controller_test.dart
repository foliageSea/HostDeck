import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:host_deck/server/features/logs/server_log_controller.dart';
import 'package:host_deck/server/features/logs/server_log_service.dart';
import 'package:logging/logging.dart';
import 'package:shelf/shelf.dart';

void main() {
  late ServerLogService service;
  late ServerLogController controller;
  late Logger logger;

  setUp(() {
    service = ServerLogService();
    controller = ServerLogController(service);
    logger = Logger('ServerLogControllerTest');
  });

  tearDown(() => service.dispose());

  test(
    'streams connected and replayed log events with standard headers',
    () async {
      logger.info('one');
      logger.warning('two');
      final response = controller.stream(
        Request(
          'GET',
          Uri.parse('http://localhost/api/logs/stream'),
          headers: {'last-event-id': '1'},
        ),
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
      final initialChunk = utf8.decode(iterator.current);
      expect(initialChunk, startsWith(': '));
      expect(
        initialChunk,
        endsWith(
          'event: connected\nretry: 3000\ndata: {"cursor":1,"requestedCursor":1,"oldestId":1,"latestId":2,"replayTruncated":false}\n\n',
        ),
      );
      expect(await iterator.moveNext(), isTrue);
      final event = utf8.decode(iterator.current);
      expect(event, startsWith('id: 2\nevent: log\n'));
      expect(event, contains('"message":"two"'));
      expect(service.subscriberCount, 1);

      await iterator.cancel();
      await Future<void>.delayed(Duration.zero);
      expect(service.subscriberCount, 0);
    },
  );

  test('Last-Event-ID takes precedence over the cursor query', () async {
    logger.info('one');
    logger.info('two');
    final response = controller.stream(
      Request(
        'GET',
        Uri.parse('http://localhost/api/logs/stream?cursor=0'),
        headers: {'Last-Event-ID': '1'},
      ),
    );

    final iterator = StreamIterator<List<int>>(response.read());
    await iterator.moveNext();
    expect(utf8.decode(iterator.current), contains('"cursor":1'));
    await iterator.moveNext();
    expect(utf8.decode(iterator.current), startsWith('id: 2\n'));
    await iterator.cancel();
  });

  test('resets a cursor ahead of the current process ids', () async {
    logger.info('current process');
    final response = controller.stream(
      Request(
        'GET',
        Uri.parse('http://localhost/api/logs/stream'),
        headers: {'Last-Event-ID': '500'},
      ),
    );

    final iterator = StreamIterator<List<int>>(response.read());
    await iterator.moveNext();
    final connected = utf8.decode(iterator.current);
    expect(connected, contains('"cursor":null'));
    expect(connected, contains('"requestedCursor":500'));
    expect(connected, contains('"replayTruncated":true'));
    await iterator.moveNext();
    expect(
      utf8.decode(iterator.current),
      contains('"message":"current process"'),
    );
    await iterator.cancel();
  });
}
