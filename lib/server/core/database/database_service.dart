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

    // v5 -> v6: Persist background file operation tasks and their items.
    if (currentVersion < 6) {
      _db.execute('''
        CREATE TABLE IF NOT EXISTS file_tasks (
          id TEXT PRIMARY KEY,
          connectionId TEXT NOT NULL,
          type TEXT NOT NULL,
          status TEXT NOT NULL,
          errorMessage TEXT,
          createdAt INTEGER NOT NULL,
          startedAt INTEGER,
          finishedAt INTEGER
        )
      ''');
      _db.execute('''
        CREATE TABLE IF NOT EXISTS file_task_items (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          taskId TEXT NOT NULL,
          itemOrder INTEGER NOT NULL,
          sourcePath TEXT NOT NULL,
          targetPath TEXT,
          status TEXT NOT NULL,
          errorMessage TEXT,
          startedAt INTEGER,
          finishedAt INTEGER,
          FOREIGN KEY(taskId) REFERENCES file_tasks(id) ON DELETE CASCADE
        )
      ''');
      _db.execute('''
        CREATE INDEX IF NOT EXISTS idx_file_tasks_connection_created
        ON file_tasks(connectionId, createdAt DESC)
      ''');
      _db.execute('''
        CREATE INDEX IF NOT EXISTS idx_file_task_items_task_order
        ON file_task_items(taskId, itemOrder)
      ''');
      _setVersion(6);
    }

    // v6 -> v7: Store Docker registry metadata per remote host and user.
    if (currentVersion < 7) {
      _db.execute('''
        CREATE TABLE IF NOT EXISTS docker_registries (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          targetKey TEXT NOT NULL,
          address TEXT NOT NULL,
          name TEXT NOT NULL,
          namespace TEXT NOT NULL DEFAULT '',
          authentication INTEGER NOT NULL DEFAULT 0,
          username TEXT NOT NULL DEFAULT '',
          UNIQUE(targetKey, address)
        )
      ''');
      _db.execute('''
        CREATE INDEX IF NOT EXISTS idx_docker_registries_target
        ON docker_registries(targetKey, id)
      ''');
      _setVersion(7);
    }

    // v7 -> v8: Upgrade installations created with the temporary connectionId key.
    if (currentVersion < 8) {
      final columns = _db
          .select('PRAGMA table_info(docker_registries)')
          .map((row) => row['name'] as String)
          .toSet();
      if (columns.contains('connectionId') && !columns.contains('targetKey')) {
        _db.execute(
          'ALTER TABLE docker_registries RENAME COLUMN connectionId TO targetKey',
        );
      }
      _db.execute('DROP INDEX IF EXISTS idx_docker_registries_connection');
      _db.execute('''
        CREATE INDEX IF NOT EXISTS idx_docker_registries_target
        ON docker_registries(targetKey, id)
      ''');
      _setVersion(8);
    }

    // v8 -> v9: Associate cron tasks with stable saved server IDs.
    if (currentVersion < 9) {
      _db.execute('''
        CREATE TABLE IF NOT EXISTS cron_tasks (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          connectionId TEXT NOT NULL,
          serverId INTEGER,
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
        CREATE TABLE IF NOT EXISTS cron_execution_history (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          taskId INTEGER NOT NULL,
          connectionId TEXT NOT NULL,
          serverId INTEGER,
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
      final taskColumns = _db
          .select('PRAGMA table_info(cron_tasks)')
          .map((row) => row['name'] as String)
          .toSet();
      if (!taskColumns.contains('serverId')) {
        _db.execute('ALTER TABLE cron_tasks ADD COLUMN serverId INTEGER');
      }

      final historyColumns = _db
          .select('PRAGMA table_info(cron_execution_history)')
          .map((row) => row['name'] as String)
          .toSet();
      if (!historyColumns.contains('serverId')) {
        _db.execute(
          'ALTER TABLE cron_execution_history ADD COLUMN serverId INTEGER',
        );
      }
      _db.execute('''
        CREATE INDEX IF NOT EXISTS idx_cron_tasks_server_updated
        ON cron_tasks(serverId, updatedAt DESC)
      ''');
      _db.execute('''
        CREATE INDEX IF NOT EXISTS idx_cron_history_server_task_started
        ON cron_execution_history(serverId, taskId, startedAt DESC)
      ''');
      _setVersion(9);
    }

    // v9 -> v10: Persist AI agent configuration and target-bound chat history.
    if (currentVersion < 10) {
      _db.execute('''
        CREATE TABLE IF NOT EXISTS ai_agent_settings (
          id INTEGER PRIMARY KEY CHECK (id = 1),
          baseUrl TEXT NOT NULL,
          model TEXT NOT NULL,
          encryptedApiKey TEXT,
          updatedAt INTEGER NOT NULL
        )
      ''');
      _db.execute('''
        CREATE TABLE IF NOT EXISTS ai_agent_conversations (
          id TEXT PRIMARY KEY,
          targetKey TEXT NOT NULL,
          title TEXT NOT NULL DEFAULT '新对话',
          createdAt INTEGER NOT NULL,
          updatedAt INTEGER NOT NULL
        )
      ''');
      _db.execute('''
        CREATE INDEX IF NOT EXISTS idx_ai_agent_conversations_target_updated
        ON ai_agent_conversations(targetKey, updatedAt DESC)
      ''');
      _db.execute('''
        CREATE TABLE IF NOT EXISTS ai_agent_messages (
          id TEXT PRIMARY KEY,
          conversationId TEXT NOT NULL,
          role TEXT NOT NULL CHECK (role IN ('user', 'assistant')),
          content TEXT NOT NULL,
          createdAt INTEGER NOT NULL,
          FOREIGN KEY(conversationId) REFERENCES ai_agent_conversations(id)
            ON DELETE CASCADE
        )
      ''');
      _db.execute('''
        CREATE INDEX IF NOT EXISTS idx_ai_agent_messages_conversation_created
        ON ai_agent_messages(conversationId, createdAt, id)
      ''');
      _setVersion(10);
    }

    // v10 -> v11: Add human-readable AI conversation titles.
    if (currentVersion < 11) {
      final columns = _db
          .select('PRAGMA table_info(ai_agent_conversations)')
          .map((row) => row['name'] as String)
          .toSet();
      if (!columns.contains('title')) {
        _db.execute(
          "ALTER TABLE ai_agent_conversations ADD COLUMN title TEXT NOT NULL DEFAULT '新对话'",
        );
      }
      _setVersion(11);
    }

    // v11 -> v12: Add Streamable HTTP MCP server configuration.
    if (currentVersion < 12) {
      _db.execute('''
        CREATE TABLE IF NOT EXISTS ai_agent_mcp_servers (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          url TEXT NOT NULL,
          encryptedHeaders TEXT,
          enabled INTEGER NOT NULL DEFAULT 1,
          createdAt INTEGER NOT NULL,
          updatedAt INTEGER NOT NULL
        )
      ''');
      _db.execute('''
        CREATE INDEX IF NOT EXISTS idx_ai_agent_mcp_servers_enabled_name
        ON ai_agent_mcp_servers(enabled DESC, name COLLATE NOCASE)
      ''');
      _setVersion(12);
    }

    // v12 -> v13: Store the set of AI models available for quick switching.
    if (currentVersion < 13) {
      final columns = _db
          .select('PRAGMA table_info(ai_agent_settings)')
          .map((row) => row['name'] as String)
          .toSet();
      if (!columns.contains('models')) {
        _db.execute(
          "ALTER TABLE ai_agent_settings ADD COLUMN models TEXT NOT NULL DEFAULT '[]'",
        );
      }
      _setVersion(13);
    }

    // v13 -> v14: Persist image attachments for multimodal AI messages.
    if (currentVersion < 14) {
      final columns = _db
          .select('PRAGMA table_info(ai_agent_messages)')
          .map((row) => row['name'] as String)
          .toSet();
      if (!columns.contains('attachments')) {
        _db.execute(
          "ALTER TABLE ai_agent_messages ADD COLUMN attachments TEXT NOT NULL DEFAULT '[]'",
        );
      }
      _setVersion(14);
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
      stmt.close();
    }
  }

  void _setVersion(int version) {
    _db.execute('DELETE FROM schema_version');
    _db.execute('INSERT INTO schema_version (version) VALUES (?)', [version]);
  }

  void close() {
    _db.close();
  }
}
