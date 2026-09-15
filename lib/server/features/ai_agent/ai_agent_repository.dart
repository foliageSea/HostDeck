import 'package:host_deck/server/core/database/database_service.dart';
import 'package:host_deck/server/features/ai_agent/ai_agent_models.dart';

class AiAgentStoredSettings {
  final String baseUrl;
  final String model;
  final String? encryptedApiKey;

  const AiAgentStoredSettings({
    required this.baseUrl,
    required this.model,
    this.encryptedApiKey,
  });
}

class AiAgentRepository {
  final DatabaseService _database;

  AiAgentRepository(this._database);

  AiAgentStoredSettings getSettings() {
    final rows = _database.db.select(
      'SELECT baseUrl, model, encryptedApiKey FROM ai_agent_settings WHERE id = 1',
    );
    if (rows.isEmpty) {
      return const AiAgentStoredSettings(
        baseUrl: AiAgentSettings.defaultBaseUrl,
        model: AiAgentSettings.defaultModel,
      );
    }
    final row = rows.first;
    return AiAgentStoredSettings(
      baseUrl: row['baseUrl'] as String,
      model: row['model'] as String,
      encryptedApiKey: row['encryptedApiKey'] as String?,
    );
  }

  void saveSettings(AiAgentStoredSettings settings) {
    _database.db.execute(
      '''
      INSERT INTO ai_agent_settings
        (id, baseUrl, model, encryptedApiKey, updatedAt)
      VALUES (1, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        baseUrl = excluded.baseUrl,
        model = excluded.model,
        encryptedApiKey = excluded.encryptedApiKey,
        updatedAt = excluded.updatedAt
      ''',
      [
        settings.baseUrl,
        settings.model,
        settings.encryptedApiKey,
        DateTime.now().millisecondsSinceEpoch,
      ],
    );
  }

  AiAgentConversation createConversation(String id, String targetKey) {
    final now = DateTime.now().millisecondsSinceEpoch;
    _database.db.execute(
      '''INSERT INTO ai_agent_conversations
         (id, targetKey, createdAt, updatedAt) VALUES (?, ?, ?, ?)''',
      [id, targetKey, now, now],
    );
    return AiAgentConversation(
      id: id,
      targetKey: targetKey,
      title: '新对话',
      createdAt: now,
      updatedAt: now,
    );
  }

  List<AiAgentConversation> listConversations(
    String targetKey, {
    int limit = 50,
    int offset = 0,
  }) {
    final safeLimit = limit.clamp(1, 100);
    final safeOffset = offset.clamp(0, 1000000);
    return _database.db
        .select(
          '''SELECT id, targetKey, title, createdAt, updatedAt
             FROM ai_agent_conversations WHERE targetKey = ?
             ORDER BY updatedAt DESC LIMIT ? OFFSET ?''',
          [targetKey, safeLimit, safeOffset],
        )
        .map(_conversationFromRow)
        .toList();
  }

  AiAgentConversation? getConversation(String id, String targetKey) {
    final rows = _database.db.select(
      '''SELECT id, targetKey, title, createdAt, updatedAt
         FROM ai_agent_conversations WHERE id = ? AND targetKey = ?''',
      [id, targetKey],
    );
    return rows.isEmpty ? null : _conversationFromRow(rows.first);
  }

  bool deleteConversation(String id, String targetKey) {
    _database.db.execute('BEGIN');
    try {
      _database.db.execute(
        '''DELETE FROM ai_agent_messages WHERE conversationId IN (
             SELECT id FROM ai_agent_conversations
             WHERE id = ? AND targetKey = ?
           )''',
        [id, targetKey],
      );
      _database.db.execute(
        'DELETE FROM ai_agent_conversations WHERE id = ? AND targetKey = ?',
        [id, targetKey],
      );
      final deleted = _database.db.updatedRows > 0;
      _database.db.execute('COMMIT');
      return deleted;
    } catch (_) {
      _database.db.execute('ROLLBACK');
      rethrow;
    }
  }

  AiAgentMessage addMessage({
    required String id,
    required String conversationId,
    required String role,
    required String content,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    _database.db.execute(
      '''INSERT INTO ai_agent_messages
         (id, conversationId, role, content, createdAt)
         VALUES (?, ?, ?, ?, ?)''',
      [id, conversationId, role, content, now],
    );
    _database.db.execute(
      'UPDATE ai_agent_conversations SET updatedAt = ? WHERE id = ?',
      [now, conversationId],
    );
    if (role == 'user') {
      _database.db.execute(
        '''UPDATE ai_agent_conversations SET title = ?
           WHERE id = ? AND title = '新对话' ''',
        [_titleFromContent(content), conversationId],
      );
    }
    return AiAgentMessage(
      id: id,
      conversationId: conversationId,
      role: role,
      content: content,
      createdAt: now,
    );
  }

  List<AiAgentMessage> listMessages(String conversationId, {int limit = 100}) {
    final safeLimit = limit.clamp(1, 200);
    final rows = _database.db.select(
      '''SELECT id, conversationId, role, content, createdAt FROM (
           SELECT id, conversationId, role, content, createdAt
           FROM ai_agent_messages WHERE conversationId = ?
           ORDER BY createdAt DESC, id DESC LIMIT ?
         ) ORDER BY createdAt, id''',
      [conversationId, safeLimit],
    );
    return rows
        .map(
          (row) => AiAgentMessage(
            id: row['id'] as String,
            conversationId: row['conversationId'] as String,
            role: row['role'] as String,
            content: row['content'] as String,
            createdAt: row['createdAt'] as int,
          ),
        )
        .toList();
  }

  AiAgentConversation _conversationFromRow(dynamic row) => AiAgentConversation(
    id: row['id'] as String,
    targetKey: row['targetKey'] as String,
    title: row['title'] as String,
    createdAt: row['createdAt'] as int,
    updatedAt: row['updatedAt'] as int,
  );

  String _titleFromContent(String content) {
    final normalized = content.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.isEmpty) return '新对话';
    return normalized.length <= 40
        ? normalized
        : '${normalized.substring(0, 40)}...';
  }
}
