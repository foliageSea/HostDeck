import 'dart:async';
import 'dart:io';

import 'package:host_deck/utils/daily_file_logger.dart';
import 'package:logging/logging.dart';

class ServerLoggingHandle {
  final StreamSubscription<LogRecord> _subscription;
  final DailyFileLogger? _fileLogger;

  const ServerLoggingHandle(this._subscription, this._fileLogger);

  bool get isFileLoggingEnabled => _fileLogger != null;

  Future<void> flush() async {
    await _fileLogger?.flush();
  }

  Future<void> close() async {
    await _subscription.cancel();
    await _fileLogger?.close();
  }
}

Future<ServerLoggingHandle> configureServerLogging({
  required Directory directory,
  required int maxDays,
}) async {
  Logger.root.level = Level.ALL;
  DailyFileLogger? fileLogger;
  try {
    fileLogger = DailyFileLogger(
      directory: directory,
      maxDays: maxDays,
      onError: (error, stackTrace) {
        stderr.writeln('Failed to write log file: $error');
        stderr.writeln(stackTrace);
      },
    );
    await fileLogger.initialize();
  } catch (e, st) {
    stderr.writeln('Failed to initialize file logging: $e');
    stderr.writeln(st);
    fileLogger = null;
  }

  final subscription = Logger.root.onRecord.listen((record) {
    final message = formatLogRecord(record);
    stderr.writeln(formatConsoleLogRecord(record));
    if (record.error != null) {
      stderr.writeln('Error: ${record.error}');
    }
    if (record.stackTrace != null) {
      stderr.writeln(record.stackTrace);
    }
    final details = StringBuffer(message);
    if (record.error != null) {
      details.write('\nError: ${record.error}');
    }
    if (record.stackTrace != null) {
      details.write('\n${record.stackTrace}');
    }
    fileLogger?.write(details.toString());
  });
  return ServerLoggingHandle(subscription, fileLogger);
}

String formatLogRecord(LogRecord record) {
  const loggerNameWidth = 24;
  final timestamp = _formatLogTimestamp(record.time);
  final level = record.level.name.padRight(7);
  final loggerName = record.loggerName.padRight(loggerNameWidth);
  return '$timestamp $level $loggerName | ${record.message}';
}

String formatConsoleLogRecord(LogRecord record) {
  const loggerNameWidth = 24;
  const reset = '\x1B[0m';
  final timestamp = _formatLogTimestamp(record.time);
  final level = record.level.name.padRight(7);
  final loggerName = record.loggerName.padRight(loggerNameWidth);
  return '$timestamp ${_ansiColorForLevel(record.level)}$level$reset '
      '$loggerName | ${record.message}';
}

String _formatLogTimestamp(DateTime value) {
  final local = value.toLocal();
  String pad(int number, int width) => number.toString().padLeft(width, '0');
  return '${pad(local.year, 4)}-${pad(local.month, 2)}-${pad(local.day, 2)} '
      '${pad(local.hour, 2)}:${pad(local.minute, 2)}:${pad(local.second, 2)}.'
      '${pad(local.millisecond, 3)}';
}

String _ansiColorForLevel(Level level) {
  if (level >= Level.SEVERE) return '\x1B[31m';
  if (level >= Level.WARNING) return '\x1B[33m';
  if (level >= Level.INFO) return '\x1B[36m';
  if (level >= Level.CONFIG) return '\x1B[34m';
  return '\x1B[90m';
}
