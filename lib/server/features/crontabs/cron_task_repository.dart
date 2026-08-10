import 'package:host_deck/server/core/database/database_service.dart';
import 'package:host_deck/server/features/crontabs/cron_task.dart';

class CronTaskRepository {
  static const maxHistoryPerTask = 200;
  final DatabaseService _databaseService;

  CronTaskRepository(this._databaseService);

  List<CronTask> list(String connectionId) => _databaseService.db
      .select(
        'SELECT * FROM cron_tasks WHERE connectionId = ? ORDER BY updatedAt DESC, id DESC',
        [connectionId],
      )
      .map(_taskFromRow)
      .toList();

  CronTask? get(int id) {
    final rows = _databaseService.db.select(
      'SELECT * FROM cron_tasks WHERE id = ?',
      [id],
    );
    return rows.isEmpty ? null : _taskFromRow(rows.first);
  }

  CronTask add(CronTask task) {
    final now = DateTime.now().millisecondsSinceEpoch;
    _databaseService.db.execute(
      '''INSERT INTO cron_tasks
        (connectionId, name, schedule, command, enabled, templateType, createdAt, updatedAt)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)''',
      [
        task.connectionId,
        task.name,
        task.schedule,
        task.command,
        task.enabled ? 1 : 0,
        task.templateType,
        now,
        now,
      ],
    );
    return CronTask(
      id: _databaseService.db.lastInsertRowId,
      connectionId: task.connectionId,
      name: task.name,
      schedule: task.schedule,
      command: task.command,
      enabled: task.enabled,
      templateType: task.templateType,
      createdAt: now,
      updatedAt: now,
    );
  }

  void restore(CronTask task) {
    _databaseService.db.execute(
      '''INSERT OR REPLACE INTO cron_tasks
        (id, connectionId, name, schedule, command, enabled, templateType, createdAt, updatedAt)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)''',
      [
        task.id,
        task.connectionId,
        task.name,
        task.schedule,
        task.command,
        task.enabled ? 1 : 0,
        task.templateType,
        task.createdAt,
        task.updatedAt,
      ],
    );
  }

  CronTask? update(int id, CronTask task) {
    final existing = get(id);
    if (existing == null) return null;
    final now = DateTime.now().millisecondsSinceEpoch;
    _databaseService.db.execute(
      '''UPDATE cron_tasks SET name = ?, schedule = ?, command = ?, enabled = ?,
        templateType = ?, updatedAt = ? WHERE id = ?''',
      [
        task.name,
        task.schedule,
        task.command,
        task.enabled ? 1 : 0,
        task.templateType,
        now,
        id,
      ],
    );
    return CronTask(
      id: id,
      connectionId: existing.connectionId,
      name: task.name,
      schedule: task.schedule,
      command: task.command,
      enabled: task.enabled,
      templateType: task.templateType,
      createdAt: existing.createdAt,
      updatedAt: now,
    );
  }

  bool delete(int id) {
    _databaseService.db.execute('DELETE FROM cron_tasks WHERE id = ?', [id]);
    return _databaseService.db.updatedRows > 0;
  }

  List<CronExecutionHistory> listHistory(
    int taskId, {
    int limit = 100,
    int offset = 0,
  }) {
    return _databaseService.db
        .select(
          '''SELECT * FROM cron_execution_history WHERE taskId = ?
         ORDER BY startedAt DESC, id DESC LIMIT ? OFFSET ?''',
          [taskId, limit.clamp(1, 200), offset < 0 ? 0 : offset],
        )
        .map(_historyFromRow)
        .toList();
  }

  void addHistory(CronExecutionHistory entry) {
    _databaseService.db.execute(
      '''INSERT OR IGNORE INTO cron_execution_history
        (taskId, connectionId, triggerType, startedAt, finishedAt, durationMs, exitCode, status, stdout, stderr, createdAt)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
      [
        entry.taskId,
        entry.connectionId,
        entry.triggerType,
        entry.startedAt,
        entry.finishedAt,
        entry.durationMs,
        entry.exitCode,
        entry.status,
        _truncate(entry.stdout),
        _truncate(entry.stderr),
        DateTime.now().millisecondsSinceEpoch,
      ],
    );
    _databaseService.db.execute(
      '''DELETE FROM cron_execution_history WHERE taskId = ? AND id NOT IN (
        SELECT id FROM cron_execution_history WHERE taskId = ? ORDER BY startedAt DESC, id DESC LIMIT ?
      )''',
      [entry.taskId, entry.taskId, maxHistoryPerTask],
    );
  }

  CronTask _taskFromRow(Map<String, dynamic> row) => CronTask(
    id: row['id'] as int,
    connectionId: row['connectionId'] as String,
    name: row['name'] as String,
    schedule: row['schedule'] as String,
    command: row['command'] as String,
    enabled: (row['enabled'] as int) != 0,
    templateType: row['templateType'] as String?,
    createdAt: row['createdAt'] as int,
    updatedAt: row['updatedAt'] as int,
  );

  CronExecutionHistory _historyFromRow(Map<String, dynamic> row) =>
      CronExecutionHistory(
        id: row['id'] as int,
        taskId: row['taskId'] as int,
        connectionId: row['connectionId'] as String,
        triggerType: row['triggerType'] as String,
        startedAt: row['startedAt'] as int,
        finishedAt: row['finishedAt'] as int?,
        durationMs: row['durationMs'] as int?,
        exitCode: row['exitCode'] as int?,
        status: row['status'] as String,
        stdout: row['stdout'] as String?,
        stderr: row['stderr'] as String?,
      );

  String? _truncate(String? value) => value == null || value.length <= 16000
      ? value
      : '${value.substring(0, 16000)}\n[HostDeck: 输出已截断]';
}
