import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

typedef FlushLogs = Future<void> Function();

class LogExportUnavailable implements Exception {
  final String message;

  const LogExportUnavailable(this.message);

  @override
  String toString() => message;
}

class LogExportArchive {
  final File file;
  final Directory temporaryDirectory;

  const LogExportArchive({
    required this.file,
    required this.temporaryDirectory,
  });

  Stream<List<int>> openReadAndDelete() async* {
    try {
      yield* file.openRead();
    } finally {
      if (await temporaryDirectory.exists()) {
        await temporaryDirectory.delete(recursive: true);
      }
    }
  }
}

class LogExportService {
  static const _filePrefix = 'hostdeck-server-';
  static const _fileSuffix = '.log';

  final Directory? logDirectory;
  final FlushLogs? _flushLogs;
  final Logger _log;

  LogExportService({
    required this.logDirectory,
    FlushLogs? flushLogs,
    Logger? log,
  }) : _flushLogs = flushLogs,
       _log = log ?? Logger('LogExportService');

  Future<LogExportArchive> createArchive() async {
    final directory = logDirectory;
    if (directory == null) {
      throw const LogExportUnavailable('当前运行模式未启用文件日志。');
    }

    await _flushLogs?.call();
    if (!await directory.exists()) {
      throw const LogExportUnavailable('当前没有可导出的日志。');
    }

    final files = <File>[];
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is File && _isLogFile(p.basename(entity.path))) {
        files.add(entity);
      }
    }
    files.sort(
      (left, right) => p.basename(left.path).compareTo(p.basename(right.path)),
    );
    if (files.isEmpty) {
      throw const LogExportUnavailable('当前没有可导出的日志。');
    }

    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'hostdeck_log_export_',
    );
    final archiveFile = File(
      p.join(temporaryDirectory.path, 'hostdeck-logs.zip'),
    );
    final encoder = ZipFileEncoder();
    try {
      encoder.create(archiveFile.path);
      for (final file in files) {
        await encoder.addFile(file, p.basename(file.path));
      }
      await encoder.close();
      return LogExportArchive(
        file: archiveFile,
        temporaryDirectory: temporaryDirectory,
      );
    } catch (error, stackTrace) {
      _log.warning('Failed to create log export archive.', error, stackTrace);
      try {
        await encoder.close();
      } catch (_) {
        // Preserve the original archive error.
      }
      if (await temporaryDirectory.exists()) {
        await temporaryDirectory.delete(recursive: true);
      }
      rethrow;
    }
  }

  bool _isLogFile(String fileName) {
    if (!fileName.startsWith(_filePrefix) || !fileName.endsWith(_fileSuffix)) {
      return false;
    }

    final value = fileName.substring(
      _filePrefix.length,
      fileName.length - _fileSuffix.length,
    );
    if (value.length != 10 || value[4] != '-' || value[7] != '-') {
      return false;
    }

    final year = int.tryParse(value.substring(0, 4));
    final month = int.tryParse(value.substring(5, 7));
    final day = int.tryParse(value.substring(8, 10));
    if (year == null || month == null || day == null) {
      return false;
    }
    final date = DateTime(year, month, day);
    return date.year == year && date.month == month && date.day == day;
  }
}
