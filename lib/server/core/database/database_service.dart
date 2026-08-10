import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:logging/logging.dart';

import 'package:host_deck/utils/crypto_helper.dart';
import 'package:host_deck/utils/runtime_paths.dart';

class DatabaseService {
  final _log = Logger('DatabaseService');
  final String? _dataDir;
  late final Database _db;

  Database get db => _db;

  DatabaseService({String? dataDir}) : _dataDir = dataDir;

  Future<void> init() async {
    final dir = await RuntimePaths.resolveDataDirectory(overridePath: _dataDir);
    final dbPath = p.join(dir.path, 'host_deck.db');
    final legacyDbPath = p.join(dir.path, 'ssh_tool.db');

    if (!File(dbPath).existsSync() && File(legacyDbPath).existsSync()) {
      File(legacyDbPath).renameSync(dbPath);
    }

    // Ensure directory exists
    await dir.create(recursive: true);

    _log.info('Database path: $dbPath');

    _db = sqlite3.open(dbPath);

    _migrate();
  }

  void _migrate() {
    // Create schema version table when missing.
    _db.execute('''
      CREATE TABLE IF NOT EXISTS schema_version (
        version INTEGER NOT NULL
      )
    ''');

    final versionResult = _db.select('SELECT version FROM schema_version');
    final currentVersion = versionResult.isEmpty
        ? 0
        : (versionResult.first['version'] as int);

    // v0 -> v1: Create base tables.
    if (currentVersion < 1) {
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

      _db.execute('''
        CREATE TABLE IF NOT EXISTS port_forwards (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          enabled INTEGER NOT NULL DEFAULT 0,
          bindHost TEXT NOT NULL,
          localPort INTEGER NOT NULL,
          remoteHost TEXT NOT NULL,
          remotePort INTEGER NOT NULL,
          createdAt INTEGER,
          updatedAt INTEGER
        )
      ''');

      _setVersion(1);
    }

    // v1 -> v2: Encrypt existing plaintext passwords and private keys.
    if (currentVersion < 2) {
      _migrateEncryptPasswords();
      _setVersion(2);
    }

    // v2 -> v3: Add operation logs.
    if (currentVersion < 3) {
      _db.execute('''
        CREATE TABLE IF NOT EXISTS operation_logs (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          category TEXT NOT NULL,
          action TEXT NOT NULL,
          target TEXT,
          detailJson TEXT,
          status TEXT NOT NULL,
          errorMessage TEXT,
          connectionId TEXT,
          createdAt INTEGER NOT NULL
        )
      ''');
      _db.execute('''
        CREATE INDEX IF NOT EXISTS idx_operation_logs_created_at
        ON operation_logs(createdAt DESC)
      ''');
      _setVersion(3);
    }

    // v3 -> v4: Store reusable terminal command snippets.
    if (currentVersion < 4) {
      _db.execute('''
        CREATE TABLE IF NOT EXISTS terminal_snippets (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          command TEXT NOT NULL,
          createdAt INTEGER NOT NULL,
          updatedAt INTEGER NOT NULL
        )
      ''');
      _db.execute('''
        CREATE INDEX IF NOT EXISTS idx_terminal_snippets_updated_at
        ON terminal_snippets(updatedAt DESC)
      ''');
      _setVersion(4);
    }

    // v4 -> v5: Store managed cron tasks and their remote execution history.
    if (currentVersion < 5) {
      _db.execute('''
        CREATE TABLE IF NOT EXISTS cron_tasks (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          connectionId TEXT NOT NULL,
          name TEXT NOT NULL,
          schedule TEXT NOT NULL,
          command TEXT NOT NULL,
          enabled INTEGER NOT NULL DEFAULT 1,
          templateType TEXT,
          createdAt INTEGER NOT NULL,
          updatedAt INTEGER NOT NULL
        )
      ''');
      _db.execute('''
        CREATE INDEX IF NOT EXISTS idx_cron_tasks_connection_updated
        ON cron_tasks(connectionId, updatedAt DESC)
      ''');
      _db.execute('''
        CREATE TABLE IF NOT EXISTS cron_execution_history (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          taskId INTEGER NOT NULL,
          connectionId TEXT NOT NULL,
          triggerType TEXT NOT NULL,
          startedAt INTEGER NOT NULL,
          finishedAt INTEGER,
          durationMs INTEGER,
          exitCode INTEGER,
          status TEXT NOT NULL,
          stdout TEXT,
          stderr TEXT,
          createdAt INTEGER NOT NULL,
          UNIQUE(taskId, startedAt)
        )
      ''');
      _db.execute('''
        CREATE INDEX IF NOT EXISTS idx_cron_execution_history_task_started
        ON cron_execution_history(taskId, startedAt DESC)
      ''');
      _setVersion(5);
    }
  }

  /// Encrypts existing plaintext password and privateKey values.
  void _migrateEncryptPasswords() {
    _log.info(
      'Running migration v2: encrypting stored passwords and private keys',
    );

    final rows = _db.select('SELECT id, password, privateKey FROM servers');
    if (rows.isEmpty) return;

    final stmt = _db.prepare(
      'UPDATE servers SET password = ?, privateKey = ? WHERE id = ?',
    );
    try {
      for (final row in rows) {
        final id = row['id'] as int;
        final rawPassword = row['password'] as String?;
        final rawPrivateKey = row['privateKey'] as String?;

        // Encrypt only plaintext values and keep encrypted values unchanged.
        final encPassword = CryptoHelper.isEncrypted(rawPassword)
            ? rawPassword
            : CryptoHelper.encrypt(rawPassword);
        final encPrivateKey = CryptoHelper.isEncrypted(rawPrivateKey)
            ? rawPrivateKey
            : CryptoHelper.encrypt(rawPrivateKey);

        stmt.execute([encPassword, encPrivateKey, id]);
      }
      _log.info('Migration v2 complete: ${rows.length} server(s) updated');
    } finally {
      stmt.dispose();
    }
  }

  void _setVersion(int version) {
    _db.execute('DELETE FROM schema_version');
    _db.execute('INSERT INTO schema_version (version) VALUES (?)', [version]);
  }

  void close() {
    _db.dispose();
  }
}
