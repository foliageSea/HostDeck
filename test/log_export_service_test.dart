import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:host_deck/server/features/settings/log_export_service.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory logDirectory;

  setUp(() async {
    logDirectory = await Directory.systemTemp.createTemp(
      'host_deck_log_export_test_',
    );
  });

  tearDown(() async {
    if (await logDirectory.exists()) {
      await logDirectory.delete(recursive: true);
    }
  });

  test('exports only valid daily log files in date order', () async {
    await File(
      p.join(logDirectory.path, 'hostdeck-server-2026-08-07.log'),
    ).writeAsString('day two');
    await File(
      p.join(logDirectory.path, 'hostdeck-server-2026-08-06.log'),
    ).writeAsString('day one');
    await File(
      p.join(logDirectory.path, 'hostdeck-server-2026-02-30.log'),
    ).writeAsString('invalid date');
    await File(
      p.join(logDirectory.path, 'server.log'),
    ).writeAsString('electron wrapper log');

    var flushed = false;
    final service = LogExportService(
      logDirectory: logDirectory,
      flushLogs: () async {
        flushed = true;
      },
    );
    final result = await service.createArchive();
    final temporaryDirectory = result.temporaryDirectory;
    final bytes = await result
        .openReadAndDelete()
        .expand((chunk) => chunk)
        .toList();
    final archive = ZipDecoder().decodeBytes(bytes);

    expect(flushed, isTrue);
    expect(
      archive.map((file) => file.name),
      orderedEquals([
        'hostdeck-server-2026-08-06.log',
        'hostdeck-server-2026-08-07.log',
      ]),
    );
    expect(utf8.decode(archive[0].readBytes()!), 'day one');
    expect(utf8.decode(archive[1].readBytes()!), 'day two');
    expect(await temporaryDirectory.exists(), isFalse);
  });

  test('reports when file logging is disabled', () async {
    final service = LogExportService(logDirectory: null);

    expect(
      service.createArchive,
      throwsA(
        isA<LogExportUnavailable>().having(
          (error) => error.message,
          'message',
          '当前运行模式未启用文件日志。',
        ),
      ),
    );
  });

  test('reports when no daily logs are available', () async {
    final service = LogExportService(logDirectory: logDirectory);

    expect(
      service.createArchive,
      throwsA(
        isA<LogExportUnavailable>().having(
          (error) => error.message,
          'message',
          '当前没有可导出的日志。',
        ),
      ),
    );
  });
}
