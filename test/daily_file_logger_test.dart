import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:host_deck/utils/daily_file_logger.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory logDirectory;

  setUp(() async {
    logDirectory = await Directory.systemTemp.createTemp('host_deck_log_test_');
  });

  tearDown(() async {
    await logDirectory.delete(recursive: true);
  });

  test('writes messages to the log file for the current date', () async {
    final logger = DailyFileLogger(
      directory: logDirectory,
      maxDays: 30,
      now: () => DateTime(2026, 8, 6, 10),
    );
    await logger.initialize();

    logger.write('first message');
    logger.write('Error: failure\nstack trace');
    await logger.close();

    final content = await File(
      p.join(logDirectory.path, 'hostdeck-server-2026-08-06.log'),
    ).readAsString();
    expect(content, contains('first message'));
    expect(content, contains('Error: failure\nstack trace'));
  });

  test('switches files when the local date changes', () async {
    var now = DateTime(2026, 8, 6, 23, 59);
    final logger = DailyFileLogger(
      directory: logDirectory,
      maxDays: 30,
      now: () => now,
    );
    await logger.initialize();

    logger.write('day one');
    now = DateTime(2026, 8, 7);
    logger.write('day two');
    await logger.close();

    expect(
      await File(
        p.join(logDirectory.path, 'hostdeck-server-2026-08-06.log'),
      ).readAsString(),
      contains('day one'),
    );
    expect(
      await File(
        p.join(logDirectory.path, 'hostdeck-server-2026-08-07.log'),
      ).readAsString(),
      contains('day two'),
    );
  });

  test('deletes only log files older than the retention boundary', () async {
    final expired = File(
      p.join(logDirectory.path, 'hostdeck-server-2026-07-07.log'),
    );
    final oldestRetained = File(
      p.join(logDirectory.path, 'hostdeck-server-2026-07-08.log'),
    );
    final unrelated = File(p.join(logDirectory.path, 'application.log'));
    await expired.writeAsString('expired');
    await oldestRetained.writeAsString('retained');
    await unrelated.writeAsString('unrelated');

    final logger = DailyFileLogger(
      directory: logDirectory,
      maxDays: 30,
      now: () => DateTime(2026, 8, 6),
    );
    await logger.initialize();
    await logger.close();

    expect(await expired.exists(), isFalse);
    expect(await oldestRetained.exists(), isTrue);
    expect(await unrelated.exists(), isTrue);
  });
}
