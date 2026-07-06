import 'dart:convert';

import 'package:host_deck/server/core/database/database_service.dart';
import 'package:host_deck/server/features/operation_logs/operation_log.dart';

class OperationLogRepository {
  static const maxLogs = 1000;

  final DatabaseService _databaseService;

  OperationLogRepository(this._databaseService);

  OperationLog add({
    required String category,
    required String action,
    String? target,
    Map<String, dynamic>? detail,
    String status = 'success',
    String? errorMessage,
    String? connectionId,
  }) {
    final createdAt = DateTime.now().millisecondsSinceEpoch;
    final sanitizedError = _truncate(errorMessage, 500);
    final db = _databaseService.db;

    db.execute(
      '''
      INSERT INTO operation_logs
        (category, action, target, detailJson, status, errorMessage, connectionId, createdAt)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        category,
        action,
        _truncate(target, 300),
        detail == null ? null : jsonEncode(detail),
        status,
        sanitizedError,
        connectionId,
        createdAt,
      ],
    );

    _trimOldLogs();

    return OperationLog(
      id: db.lastInsertRowId,
      category: category,
      action: action,
      target: _truncate(target, 300),
      detail: detail,
      status: status,
      errorMessage: sanitizedError,
      connectionId: connectionId,
      createdAt: createdAt,
    );
  }

  List<OperationLog> list({
    int limit = 100,
    int offset = 0,
    String? category,
    String? status,
  }) {
    final safeLimit = limit.clamp(1, 200).toInt();
    final safeOffset = offset < 0 ? 0 : offset;
    final where = <String>[];
    final args = <Object?>[];

    if (category != null && category.isNotEmpty) {
      where.add('category = ?');
      args.add(category);
    }
    if (status != null && status.isNotEmpty) {
      where.add('status = ?');
      args.add(status);
    }

    final whereSql = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';
    final rows = _databaseService.db.select(
      '''
      SELECT id, category, action, target, detailJson, status, errorMessage, connectionId, createdAt
      FROM operation_logs
      $whereSql
      ORDER BY createdAt DESC, id DESC
      LIMIT ? OFFSET ?
      ''',
      [...args, safeLimit, safeOffset],
    );

    return rows.map((row) {
      final detailJson = row['detailJson'] as String?;
      return OperationLog(
        id: row['id'] as int,
        category: row['category'] as String,
        action: row['action'] as String,
        target: row['target'] as String?,
        detail: detailJson == null
            ? null
            : jsonDecode(detailJson) as Map<String, dynamic>,
        status: row['status'] as String,
        errorMessage: row['errorMessage'] as String?,
        connectionId: row['connectionId'] as String?,
        createdAt: row['createdAt'] as int,
      );
    }).toList();
  }

  void clear() {
    _databaseService.db.execute('DELETE FROM operation_logs');
  }

  void _trimOldLogs() {
    _databaseService.db.execute(
      '''
      DELETE FROM operation_logs
      WHERE id NOT IN (
        SELECT id FROM operation_logs
        ORDER BY createdAt DESC, id DESC
        LIMIT ?
      )
      ''',
      [maxLogs],
    );
  }

  String? _truncate(String? value, int maxLength) {
    if (value == null || value.length <= maxLength) {
      return value;
    }
    return value.substring(0, maxLength);
  }
}
