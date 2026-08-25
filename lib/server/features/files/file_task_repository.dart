import 'package:host_deck/server/core/database/database_service.dart';
import 'package:host_deck/server/features/files/file_task.dart';

class FileTaskRepository {
  final DatabaseService _databaseService;

  FileTaskRepository(this._databaseService);

  void create(FileTask task) {
    final db = _databaseService.db;
    db.execute(
      'INSERT INTO file_tasks (id, connectionId, type, status, createdAt) VALUES (?, ?, ?, ?, ?)',
      [
        task.id,
        task.connectionId,
        task.type.name,
        task.status.name,
        task.createdAt,
      ],
    );
    final statement = db.prepare(
      'INSERT INTO file_task_items (taskId, itemOrder, sourcePath, targetPath, status) VALUES (?, ?, ?, ?, ?)',
    );
    try {
      for (final entry in task.items.asMap().entries) {
        statement.execute([
          task.id,
          entry.key,
          entry.value.sourcePath,
          entry.value.targetPath,
          entry.value.status.name,
        ]);
      }
    } finally {
      statement.close();
    }
  }

  FileTask? find(String id) {
    final rows = _databaseService.db.select(
      'SELECT id, connectionId, type, status, errorMessage, createdAt, startedAt, finishedAt FROM file_tasks WHERE id = ?',
      [id],
    );
    return rows.isEmpty ? null : _taskFromRow(rows.first);
  }

  List<FileTask> list({String? connectionId, int limit = 100}) {
    final rows = connectionId == null
        ? _databaseService.db.select(
            'SELECT id, connectionId, type, status, errorMessage, createdAt, startedAt, finishedAt FROM file_tasks ORDER BY createdAt DESC LIMIT ?',
            [limit.clamp(1, 200)],
          )
        : _databaseService.db.select(
            'SELECT id, connectionId, type, status, errorMessage, createdAt, startedAt, finishedAt FROM file_tasks WHERE connectionId = ? ORDER BY createdAt DESC LIMIT ?',
            [connectionId, limit.clamp(1, 200)],
          );
    return rows.map(_taskFromRow).toList();
  }

  void updateTask(String id, FileTaskStatus status, {String? errorMessage}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final isRunning = status == FileTaskStatus.running;
    final isFinished = switch (status) {
      FileTaskStatus.success ||
      FileTaskStatus.failed ||
      FileTaskStatus.cancelled => true,
      _ => false,
    };
    _databaseService.db.execute(
      'UPDATE file_tasks SET status = ?, errorMessage = ?, startedAt = CASE WHEN ? THEN COALESCE(startedAt, ?) ELSE startedAt END, finishedAt = CASE WHEN ? THEN ? ELSE finishedAt END WHERE id = ?',
      [
        status.name,
        errorMessage,
        isRunning ? 1 : 0,
        now,
        isFinished ? 1 : 0,
        now,
        id,
      ],
    );
  }

  void updateItem(int id, FileTaskStatus status, {String? errorMessage}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final isRunning = status == FileTaskStatus.running;
    final isFinished =
        status == FileTaskStatus.success ||
        status == FileTaskStatus.failed ||
        status == FileTaskStatus.cancelled;
    _databaseService.db.execute(
      'UPDATE file_task_items SET status = ?, errorMessage = ?, startedAt = CASE WHEN ? THEN COALESCE(startedAt, ?) ELSE startedAt END, finishedAt = CASE WHEN ? THEN ? ELSE finishedAt END WHERE id = ?',
      [
        status.name,
        errorMessage,
        isRunning ? 1 : 0,
        now,
        isFinished ? 1 : 0,
        now,
        id,
      ],
    );
  }

  void markUnfinishedAsFailed() {
    final now = DateTime.now().millisecondsSinceEpoch;
    _databaseService.db.execute(
      "UPDATE file_tasks SET status = 'failed', errorMessage = '服务已重启，远端操作状态无法恢复。', finishedAt = ? WHERE status IN ('queued', 'running')",
      [now],
    );
    _databaseService.db.execute(
      "UPDATE file_task_items SET status = 'failed', errorMessage = '服务已重启，远端操作状态无法恢复。', finishedAt = ? WHERE status IN ('queued', 'running')",
      [now],
    );
  }

  FileTask _taskFromRow(dynamic row) {
    final id = row['id'] as String;
    final items = _databaseService.db
        .select(
          'SELECT id, sourcePath, targetPath, status, errorMessage, startedAt, finishedAt FROM file_task_items WHERE taskId = ? ORDER BY itemOrder ASC',
          [id],
        )
        .map(
          (item) => FileTaskItem(
            id: item['id'] as int,
            sourcePath: item['sourcePath'] as String,
            targetPath: item['targetPath'] as String?,
            status: FileTaskStatus.values.byName(item['status'] as String),
            errorMessage: item['errorMessage'] as String?,
            startedAt: item['startedAt'] as int?,
            finishedAt: item['finishedAt'] as int?,
          ),
        )
        .toList();
    return FileTask(
      id: id,
      connectionId: row['connectionId'] as String,
      type: FileTaskType.values.byName(row['type'] as String),
      status: FileTaskStatus.values.byName(row['status'] as String),
      errorMessage: row['errorMessage'] as String?,
      createdAt: row['createdAt'] as int,
      startedAt: row['startedAt'] as int?,
      finishedAt: row['finishedAt'] as int?,
      items: items,
    );
  }
}
