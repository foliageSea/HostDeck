import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

typedef LogClock = DateTime Function();

class DailyFileLogger {
  static const String _filePrefix = 'hostdeck-server-';
  static const String _fileSuffix = '.log';

  final Directory directory;
  final int maxDays;
  final LogClock _now;
  final void Function(Object error, StackTrace stackTrace)? _onError;

  Future<void> _pendingWrite = Future<void>.value();
  IOSink? _sink;
  DateTime? _currentDate;
  bool _closed = false;

  DailyFileLogger({
    required this.directory,
    required this.maxDays,
    LogClock? now,
    void Function(Object error, StackTrace stackTrace)? onError,
  }) : assert(maxDays > 0),
       _now = now ?? DateTime.now,
       _onError = onError;

  Future<void> initialize() async {
    await directory.create(recursive: true);
    await _deleteExpiredFiles(_dateOnly(_now()));
  }

  void write(String message) {
    if (_closed) {
      return;
    }

    final date = _dateOnly(_now());
    _pendingWrite = _pendingWrite.then((_) => _write(message, date)).catchError(
      (Object error, StackTrace stackTrace) {
        _onError?.call(error, stackTrace);
      },
    );
  }

  Future<void> flush() async {
    if (_closed) {
      await _pendingWrite;
      return;
    }

    _pendingWrite = _pendingWrite
        .then((_) async {
          await _sink?.flush();
        })
        .catchError((Object error, StackTrace stackTrace) {
          _onError?.call(error, stackTrace);
        });
    await _pendingWrite;
  }

  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;

    await _pendingWrite;
    await _closeSink();
  }

  Future<void> _write(String message, DateTime date) async {
    if (_currentDate != date) {
      await _closeSink();
      await _deleteExpiredFiles(date);
      final file = File(p.join(directory.path, _fileName(date)));
      _sink = file.openWrite(mode: FileMode.append);
      _currentDate = date;
    }

    _sink!.writeln(message);
  }

  Future<void> _closeSink() async {
    final sink = _sink;
    _sink = null;
    _currentDate = null;
    if (sink == null) {
      return;
    }
    await sink.flush();
    await sink.close();
  }

  Future<void> _deleteExpiredFiles(DateTime today) async {
    final oldestRetainedDate = today.subtract(Duration(days: maxDays - 1));
    await for (final entity in directory.list()) {
      if (entity is! File) {
        continue;
      }

      final fileDate = _parseFileDate(p.basename(entity.path));
      if (fileDate == null) {
        continue;
      }
      if (fileDate.isBefore(oldestRetainedDate)) {
        await entity.delete();
      }
    }
  }

  static DateTime _dateOnly(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }

  static String _fileName(DateTime date) {
    String pad(int value) => value.toString().padLeft(2, '0');
    return '$_filePrefix${date.year}-${pad(date.month)}-${pad(date.day)}$_fileSuffix';
  }

  static DateTime? _parseFileDate(String fileName) {
    if (!fileName.startsWith(_filePrefix) || !fileName.endsWith(_fileSuffix)) {
      return null;
    }

    final value = fileName.substring(
      _filePrefix.length,
      fileName.length - _fileSuffix.length,
    );
    if (value.length != 10 || value[4] != '-' || value[7] != '-') {
      return null;
    }

    final year = int.tryParse(value.substring(0, 4));
    final month = int.tryParse(value.substring(5, 7));
    final day = int.tryParse(value.substring(8, 10));
    if (year == null || month == null || day == null) {
      return null;
    }

    final date = DateTime(year, month, day);
    if (date.year != year || date.month != month || date.day != day) {
      return null;
    }
    return date;
  }
}
