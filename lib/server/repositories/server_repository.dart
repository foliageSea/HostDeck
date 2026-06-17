import '../models/server_config.dart';
import '../services/database_service.dart';
import '../../utils/crypto_helper.dart';

class ServerRepository {
  final DatabaseService _dbService;

  ServerRepository(this._dbService);

  /// Builds a ServerConfig row and decrypts sensitive fields.
  ServerConfig _rowToConfig(Map<String, dynamic> row) {
    return ServerConfig(
      id: row['id'] as int,
      name: row['name'] as String,
      host: row['host'] as String,
      port: row['port'] as int,
      username: row['username'] as String,
      password: CryptoHelper.decrypt(row['password'] as String?),
      privateKey: CryptoHelper.decrypt(row['privateKey'] as String?),
      createdAt: row['createdAt'] as int?,
    );
  }

  List<ServerConfig> getAllServers() {
    final result = _dbService.db.select(
      'SELECT * FROM servers ORDER BY createdAt DESC',
    );
    return result.map((row) => _rowToConfig(row)).toList();
  }

  ServerConfig? getServer(int id) {
    final result = _dbService.db.select('SELECT * FROM servers WHERE id = ?', [
      id,
    ]);
    if (result.isEmpty) return null;
    return _rowToConfig(result.first);
  }

  ServerConfig addServer(ServerConfig server) {
    final stmt = _dbService.db.prepare(
      'INSERT INTO servers (name, host, port, username, password, privateKey, createdAt) VALUES (?, ?, ?, ?, ?, ?, ?)',
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    try {
      stmt.execute([
        server.name,
        server.host,
        server.port,
        server.username,
        CryptoHelper.encrypt(server.password),
        CryptoHelper.encrypt(server.privateKey),
        now,
      ]);
      final id = _dbService.db.lastInsertRowId;
      return ServerConfig(
        id: id,
        name: server.name,
        host: server.host,
        port: server.port,
        username: server.username,
        password: server.password,
        privateKey: server.privateKey,
        createdAt: now,
      );
    } finally {
      stmt.dispose();
    }
  }

  bool updateServer(int id, ServerConfig server) {
    final stmt = _dbService.db.prepare(
      'UPDATE servers SET name = ?, host = ?, port = ?, username = ?, password = ?, privateKey = ? WHERE id = ?',
    );
    try {
      stmt.execute([
        server.name,
        server.host,
        server.port,
        server.username,
        CryptoHelper.encrypt(server.password),
        CryptoHelper.encrypt(server.privateKey),
        id,
      ]);
      return _dbService.db.updatedRows > 0;
    } finally {
      stmt.dispose();
    }
  }

  bool deleteServer(int id) {
    _dbService.db.execute('DELETE FROM servers WHERE id = ?', [id]);
    return _dbService.db.updatedRows > 0;
  }
}
