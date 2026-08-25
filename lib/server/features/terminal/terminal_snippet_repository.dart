import 'package:host_deck/server/core/database/database_service.dart';
import 'package:host_deck/server/features/terminal/terminal_snippet.dart';

class TerminalSnippetRepository {
  final DatabaseService _dbService;

  TerminalSnippetRepository(this._dbService);

  List<TerminalSnippet> getAll() {
    final result = _dbService.db.select(
      'SELECT * FROM terminal_snippets ORDER BY updatedAt DESC, id DESC',
    );
    return result.map(_fromRow).toList();
  }

  TerminalSnippet add(TerminalSnippet snippet) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final stmt = _dbService.db.prepare(
      'INSERT INTO terminal_snippets (name, command, createdAt, updatedAt) VALUES (?, ?, ?, ?)',
    );
    try {
      stmt.execute([snippet.name, snippet.command, now, now]);
      return TerminalSnippet(
        id: _dbService.db.lastInsertRowId,
        name: snippet.name,
        command: snippet.command,
        createdAt: now,
        updatedAt: now,
      );
    } finally {
      stmt.close();
    }
  }

  TerminalSnippet? update(int id, TerminalSnippet snippet) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final stmt = _dbService.db.prepare(
      'UPDATE terminal_snippets SET name = ?, command = ?, updatedAt = ? WHERE id = ?',
    );
    try {
      stmt.execute([snippet.name, snippet.command, now, id]);
      if (_dbService.db.updatedRows == 0) {
        return null;
      }
    } finally {
      stmt.close();
    }

    final result = _dbService.db.select(
      'SELECT * FROM terminal_snippets WHERE id = ?',
      [id],
    );
    return result.isEmpty ? null : _fromRow(result.first);
  }

  bool delete(int id) {
    _dbService.db.execute('DELETE FROM terminal_snippets WHERE id = ?', [id]);
    return _dbService.db.updatedRows > 0;
  }

  TerminalSnippet _fromRow(Map<String, dynamic> row) {
    return TerminalSnippet(
      id: row['id'] as int,
      name: row['name'] as String,
      command: row['command'] as String,
      createdAt: row['createdAt'] as int,
      updatedAt: row['updatedAt'] as int,
    );
  }
}
