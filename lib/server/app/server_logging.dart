import 'dart:async';
import 'dart:io';

import 'package:host_deck/utils/daily_file_logger.dart';
import 'package:host_deck/server/features/logs/server_log_entry.dart';
import 'package:host_deck/server/features/logs/server_log_service.dart';
import 'package:logging/logging.dart';

class ServerLoggingHandle {
  final StreamSubscription<ServerLogEntry> _subscription;
  final DailyFileLogger? _fileLogger;
  final ServerLogService logService;
  final bool _ownsLogService;

  const ServerLoggingHandle(
    this._subscription,
    this._fileLogger,
    this.logService,
    this._ownsLogService,
  );

  bool get isFileLoggingEnabled => _fileLogger != null;

  Future<void> flush() async {
    await _fileLogger?.flush();
  }

  Future<void> close() async {
    await _subscription.cancel();
    await _fileLogger?.close();
    if (_ownsLogService) {
      await logService.dispose();
    }
  }
}

Future<ServerLoggingHandle> configureServerLogging({
  required Directory directory,
  required int maxDays,
  ServerLogService? logService,
}) async {
  final effectiveLogService = logService ?? ServerLogService();
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

  final subscription = effectiveLogService.subscribe().listen((entry) {
    final message = formatServerLogEntry(entry);
    stderr.writeln(formatConsoleServerLogEntry(entry));
    if (entry.error != null) {
      stderr.writeln('Error: ${entry.error}');
    }
    if (entry.stackTrace != null) {
      stderr.writeln(entry.stackTrace);
    }
    final details = StringBuffer(message);
    if (entry.error != null) {
      details.write('\nError: ${entry.error}');
    }
    if (entry.stackTrace != null) {
      details.write('\n${entry.stackTrace}');
    }
    fileLogger?.write(details.toString());
  });
  return ServerLoggingHandle(
    subscription,
    fileLogger,
    effectiveLogService,
    logService == null,
  );
}

String formatLogRecord(LogRecord record) {
  return formatServerLogEntry(ServerLogEntry.fromRecord(0, record));
}

String formatServerLogEntry(ServerLogEntry entry) {
  final timestamp = _formatLogTimestamp(entry.timestamp);
  final level = entry.level.padRight(7);
  final loggerName = _formatLoggerName(entry.logger);
  return '$timestamp $level $loggerName | ${entry.message}';
}

String formatConsoleLogRecord(LogRecord record) {
  return formatConsoleServerLogEntry(ServerLogEntry.fromRecord(0, record));
}

String formatConsoleServerLogEntry(ServerLogEntry entry) {
  const reset = '\x1B[0m';
  final timestamp = _formatLogTimestamp(entry.timestamp);
  final level = entry.level.padRight(7);
  final loggerName = _formatLoggerName(entry.logger);
  return '$timestamp ${_ansiColorForLevel(Level(entry.level, entry.levelValue))}$level$reset '
      '$loggerName | ${entry.message}';
}

String _formatLoggerName(String loggerName) {
  const width = 24;
  const truncation = '...';
  if (loggerName.length <= width) return loggerName.padRight(width);
  return '${loggerName.substring(0, width - truncation.length)}$truncation';
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
