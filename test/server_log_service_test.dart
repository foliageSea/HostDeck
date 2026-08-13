import 'package:flutter_test/flutter_test.dart';
import 'package:host_deck/server/features/logs/server_log_service.dart';
import 'package:logging/logging.dart';

void main() {
  late ServerLogService service;
  late Logger logger;

  setUp(() {
    service = ServerLogService(capacity: 3);
    logger = Logger('ServerLogServiceTest');
  });

  tearDown(() => service.dispose());

  test('structures records with monotonic ids and keeps a ring buffer', () {
    for (var index = 1; index <= 4; index++) {
      logger.info('message $index');
    }

    expect(service.entries.map((entry) => entry.id), [2, 3, 4]);
    expect(service.oldestId, 2);
    expect(service.latestId, 4);
    expect(service.isReplayTruncated(0), isTrue);
    expect(service.isReplayTruncated(1), isFalse);
    expect(service.isReplayTruncated(5), isTrue);
    expect(service.resolveCursor(3), 3);
    expect(service.resolveCursor(5), isNull);
    final entry = service.entries.last;
    expect(entry.logger, 'ServerLogServiceTest');
    expect(entry.level, 'INFO');
    expect(entry.message, 'message 4');
    expect(entry.toJson(), containsPair('id', 4));
    expect(entry.toJson()['timestamp'], endsWith('Z'));
  });

  test('replays entries after the cursor then continues live', () async {
    logger.info('first');
    logger.info('second');

    final received = <String>[];
    final subscription = service
        .subscribe(afterId: 1)
        .listen((entry) => received.add(entry.message));
    logger.info('third');
    await Future<void>.delayed(Duration.zero);

    expect(received, ['second', 'third']);
    expect(service.subscriberCount, 1);
    await subscription.cancel();
    expect(service.subscriberCount, 0);
  });

  test('dispose is idempotent and stops collecting root logs', () async {
    logger.info('before');
    await service.dispose();
    await service.dispose();
    logger.info('after');

    expect(service.entries.map((entry) => entry.message), ['before']);
  });

  test('resets a cursor from a previous process when the buffer is empty', () {
    expect(service.isReplayTruncated(500), isTrue);
    expect(service.resolveCursor(500), isNull);
  });
}
