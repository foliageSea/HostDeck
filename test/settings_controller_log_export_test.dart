import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:host_deck/server/features/settings/log_export_service.dart';
import 'package:host_deck/server/features/settings/settings_controller.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';

void main() {
  late Directory logDirectory;

  setUp(() async {
    logDirectory = await Directory.systemTemp.createTemp(
      'host_deck_settings_log_test_',
    );
  });

  tearDown(() async {
    if (await logDirectory.exists()) {
      await logDirectory.delete(recursive: true);
    }
  });

  test('returns the log archive as a non-cacheable attachment', () async {
    await File(
      p.join(logDirectory.path, 'hostdeck-server-2026-08-06.log'),
    ).writeAsString('server log');
    final controller = SettingsController(
      LogExportService(logDirectory: logDirectory),
    );

    final response = await controller.exportLogs(
      Request('GET', Uri.parse('http://localhost/api/settings/logs/export')),
    );
    final bytes = await response.read().expand((chunk) => chunk).toList();
    final archive = ZipDecoder().decodeBytes(bytes);

    expect(response.statusCode, HttpStatus.ok);
    expect(response.headers[HttpHeaders.contentTypeHeader], 'application/zip');
    expect(response.headers[HttpHeaders.cacheControlHeader], 'no-store');
    expect(response.headers['x-content-type-options'], 'nosniff');
    final disposition = response.headers['content-disposition']!;
    const filenamePrefix = 'attachment; filename="hostdeck-logs-';
    const filenameSuffix = '.zip"';
    expect(disposition, startsWith(filenamePrefix));
    expect(disposition, endsWith(filenameSuffix));
    final timestamp = disposition.substring(
      filenamePrefix.length,
      disposition.length - filenameSuffix.length,
    );
    expect(timestamp.length, 15);
    expect(timestamp[8], 'T');
    expect(int.tryParse(timestamp.replaceFirst('T', '')), isNotNull);
    expect(archive.single.name, 'hostdeck-server-2026-08-06.log');
    expect(utf8.decode(archive.single.readBytes()!), 'server log');
  });

  test('returns 404 when no logs are available', () async {
    final controller = SettingsController(
      LogExportService(logDirectory: logDirectory),
    );

    final response = await controller.exportLogs(
      Request('GET', Uri.parse('http://localhost/api/settings/logs/export')),
    );
    final payload = jsonDecode(await response.readAsString());

    expect(response.statusCode, HttpStatus.notFound);
    expect(payload['code'], HttpStatus.notFound);
    expect(payload['message'], '当前没有可导出的日志。');
  });
}
