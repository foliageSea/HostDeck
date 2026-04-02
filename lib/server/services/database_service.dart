import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:logging/logging.dart';

import '../../utils/runtime_paths.dart';

class DatabaseService {
  final _log = Logger('DatabaseService');
  final String? _dataDir;
  late final Database _db;

  Database get db => _db;

  DatabaseService({String? dataDir}) : _dataDir = dataDir;

  Future<void> init() async {
    final dir = await RuntimePaths.resolveDataDirectory(overridePath: _dataDir);
    final dbPath = p.join(dir.path, 'ssh_tool.db');

    // Ensure directory exists
    await dir.create(recursive: true);

    _log.info('Database path: $dbPath');

    _db = sqlite3.open(dbPath);

    _migrate();
  }

  void _migrate() {
    // Simple migration: Create table if not exists
    _db.execute('''
      CREATE TABLE IF NOT EXISTS servers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT,
        host TEXT NOT NULL,
        port INTEGER NOT NULL,
        username TEXT NOT NULL,
        password TEXT,
        privateKey TEXT,
        createdAt INTEGER
      )
    ''');
  }

  void close() {
    _db.dispose();
  }
}
