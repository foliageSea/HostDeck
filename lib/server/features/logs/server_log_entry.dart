import 'package:logging/logging.dart';

class ServerLogEntry {
  final int id;
  final DateTime timestamp;
  final String level;
  final int levelValue;
  final String logger;
  final String message;
  final String? error;
  final String? stackTrace;

  const ServerLogEntry({
    required this.id,
    required this.timestamp,
    required this.level,
    required this.levelValue,
    required this.logger,
    required this.message,
    this.error,
    this.stackTrace,
  });

  factory ServerLogEntry.fromRecord(int id, LogRecord record) {
    return ServerLogEntry(
      id: id,
      timestamp: record.time,
      level: record.level.name,
      levelValue: record.level.value,
      logger: record.loggerName,
      message: record.message,
      error: record.error?.toString(),
      stackTrace: record.stackTrace?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'timestamp': timestamp.toUtc().toIso8601String(),
    'level': level,
    'levelValue': levelValue,
    'logger': logger,
    'message': message,
    if (error != null) 'error': error,
    if (stackTrace != null) 'stackTrace': stackTrace,
  };
}
