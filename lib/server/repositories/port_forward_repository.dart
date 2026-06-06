import '../models/port_forward_rule.dart';
import '../services/database_service.dart';

class PortForwardRepository {
  final DatabaseService _dbService;

  PortForwardRepository(this._dbService);

  List<PortForwardRule> getAllRules() {
    final result = _dbService.db.select(
      'SELECT * FROM port_forwards ORDER BY createdAt DESC',
    );
    return result.map(_fromRow).toList();
  }

  PortForwardRule? getRule(int id) {
    final result = _dbService.db.select(
      'SELECT * FROM port_forwards WHERE id = ?',
      [id],
    );
    if (result.isEmpty) return null;
    return _fromRow(result.first);
  }

  PortForwardRule addRule(PortForwardRule rule) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final stmt = _dbService.db.prepare(
      'INSERT INTO port_forwards (name, enabled, bindHost, localPort, remoteHost, remotePort, createdAt, updatedAt) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
    );
    try {
      stmt.execute([
        rule.name,
        rule.enabled ? 1 : 0,
        rule.bindHost,
        rule.localPort,
        rule.remoteHost,
        rule.remotePort,
        now,
        now,
      ]);
      return rule.copyWith(
        id: _dbService.db.lastInsertRowId,
        createdAt: now,
        updatedAt: now,
      );
    } finally {
      stmt.dispose();
    }
  }

  bool updateRule(int id, PortForwardRule rule) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final stmt = _dbService.db.prepare(
      'UPDATE port_forwards SET name = ?, enabled = ?, bindHost = ?, localPort = ?, remoteHost = ?, remotePort = ?, updatedAt = ? WHERE id = ?',
    );
    try {
      stmt.execute([
        rule.name,
        rule.enabled ? 1 : 0,
        rule.bindHost,
        rule.localPort,
        rule.remoteHost,
        rule.remotePort,
        now,
        id,
      ]);
      return _dbService.db.updatedRows > 0;
    } finally {
      stmt.dispose();
    }
  }

  bool setEnabled(int id, bool enabled) {
    _dbService.db.execute(
      'UPDATE port_forwards SET enabled = ?, updatedAt = ? WHERE id = ?',
      [enabled ? 1 : 0, DateTime.now().millisecondsSinceEpoch, id],
    );
    return _dbService.db.updatedRows > 0;
  }

  bool deleteRule(int id) {
    _dbService.db.execute('DELETE FROM port_forwards WHERE id = ?', [id]);
    return _dbService.db.updatedRows > 0;
  }

  PortForwardRule _fromRow(Map<String, dynamic> row) {
    return PortForwardRule(
      id: row['id'] as int,
      name: row['name'] as String,
      enabled: (row['enabled'] as int) == 1,
      bindHost: row['bindHost'] as String,
      localPort: row['localPort'] as int,
      remoteHost: row['remoteHost'] as String,
      remotePort: row['remotePort'] as int,
      createdAt: row['createdAt'] as int?,
      updatedAt: row['updatedAt'] as int?,
    );
  }
}
