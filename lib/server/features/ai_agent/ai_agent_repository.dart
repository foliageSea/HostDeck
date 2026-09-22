import 'dart:convert';

import 'package:host_deck/server/core/database/database_service.dart';
import 'package:host_deck/server/features/ai_agent/ai_agent_models.dart';

class AiAgentStoredSettings {
  final String baseUrl;
  final String model;
  final List<AiAgentModelConfig> models;
  final String? encryptedApiKey;
  final bool showRemoteSkills;

  const AiAgentStoredSettings({
    required this.baseUrl,
    required this.model,
    this.models = const [],
    this.encryptedApiKey,
    this.showRemoteSkills = false,
  });
}

class AiAgentRepository {
  static const maxToolContentBytes = 32 * 1024;

  final DatabaseService _database;
  int _lastMessageTimestamp = 0;

  AiAgentRepository(this._database);

  AiAgentStoredSettings getSettings() {
    final rows = _database.db.select(
      'SELECT baseUrl, model, models, encryptedApiKey, showRemoteSkills FROM ai_agent_settings WHERE id = 1',
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
      models: _modelsFromJson(row['models'] as String?),
      encryptedApiKey: row['encryptedApiKey'] as String?,
      showRemoteSkills: (row['showRemoteSkills'] as int? ?? 0) != 0,
    );
  }

  void saveSettings(AiAgentStoredSettings settings) {
    _database.db.execute(
      '''
      INSERT INTO ai_agent_settings
        (id, baseUrl, model, models, encryptedApiKey, showRemoteSkills, updatedAt)
      VALUES (1, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        baseUrl = excluded.baseUrl,
        model = excluded.model,
        models = excluded.models,
        encryptedApiKey = excluded.encryptedApiKey,
        showRemoteSkills = excluded.showRemoteSkills,
        updatedAt = excluded.updatedAt
      ''',
      [
        settings.baseUrl,
        settings.model,
        jsonEncode(settings.models.map((model) => model.toJson()).toList()),
        settings.encryptedApiKey,
        settings.showRemoteSkills ? 1 : 0,
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

  AiAgentConversation? updateConversationTitle(
    String id,
    String targetKey,
    String title,
  ) {
    _database.db.execute(
      '''UPDATE ai_agent_conversations SET title = ?
         WHERE id = ? AND targetKey = ?''',
      [title, id, targetKey],
    );
    if (_database.db.updatedRows == 0) return null;
    return getConversation(id, targetKey);
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
    List<AiAgentImageAttachment> attachments = const [],
    List<AiAgentMessageToolCall> toolCalls = const [],
    String? toolCallId,
    String? toolStatus,
    Map<String, dynamic>? toolResult,
  }) {
    final now = _nextMessageTimestamp();
    final storedContent = role == 'tool'
        ? _persistableToolContent(content)
        : content;
    _database.db.execute(
      '''INSERT INTO ai_agent_messages
         (id, conversationId, role, content, attachments, metadata, createdAt)
         VALUES (?, ?, ?, ?, ?, ?, ?)''',
      [
        id,
        conversationId,
        role,
        storedContent,
        jsonEncode(
          attachments.map((attachment) => attachment.toJson()).toList(),
        ),
        _metadataJson(
          toolCalls: toolCalls,
          toolCallId: toolCallId,
          toolStatus: toolStatus,
          toolResult: toolResult,
        ),
        now,
      ],
    );
    _database.db.execute(
      'UPDATE ai_agent_conversations SET updatedAt = ? WHERE id = ?',
      [now, conversationId],
    );
    if (role == 'user') {
      _database.db.execute(
        '''UPDATE ai_agent_conversations SET title = ?
           WHERE id = ? AND title = '新对话' ''',
        [
          _titleFromContent(content, hasAttachments: attachments.isNotEmpty),
          conversationId,
        ],
      );
    }
    return AiAgentMessage(
      id: id,
      conversationId: conversationId,
      role: role,
      content: storedContent,
      attachments: attachments,
      toolCallId: toolCallId,
      toolCalls: toolCalls,
      toolStatus: toolStatus,
      toolResult: toolResult == null
          ? null
          : Map<String, dynamic>.unmodifiable(
              sanitizeAiAgentValue(toolResult) as Map<String, dynamic>,
            ),
      createdAt: now,
    );
  }

  int _nextMessageTimestamp() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final next = now > _lastMessageTimestamp ? now : _lastMessageTimestamp + 1;
    _lastMessageTimestamp = next;
    return next;
  }

  String _persistableToolContent(String content) {
    final sanitized = sanitizeAiAgentText(content);
    final bytes = utf8.encode(sanitized);
    if (bytes.length <= maxToolContentBytes) return sanitized;
    var end = maxToolContentBytes;
    while (end > 0 && (bytes[end] & 0xC0) == 0x80) {
      end--;
    }
    return '${utf8.decode(bytes.sublist(0, end), allowMalformed: true)}\n[truncated]';
  }

  String _metadataJson({
    List<AiAgentMessageToolCall> toolCalls = const [],
    String? toolCallId,
    String? toolStatus,
    Map<String, dynamic>? toolResult,
  }) {
    if (toolCalls.isEmpty &&
        toolCallId == null &&
        toolStatus == null &&
        toolResult == null) {
      return '{}';
    }
    return jsonEncode({
      'toolCallId': ?toolCallId,
      'toolStatus': ?toolStatus,
      if (toolResult != null) 'toolResult': sanitizeAiAgentValue(toolResult),
      if (toolCalls.isNotEmpty)
        'toolCalls': toolCalls.map((call) => call.toJson()).toList(),
    });
  }

  List<AiAgentMessage> listMessages(String conversationId, {int limit = 100}) {
    final safeLimit = limit.clamp(1, 200);
    final rows = _database.db.select(
      '''SELECT id, conversationId, role, content, attachments, metadata, createdAt FROM (
           SELECT id, conversationId, role, content, attachments, metadata, createdAt
           FROM ai_agent_messages WHERE conversationId = ?
           ORDER BY createdAt DESC, id DESC LIMIT ?
         ) ORDER BY createdAt, id''',
      [conversationId, safeLimit],
    );
    return rows.map(_messageFromRow).toList();
  }

  AiAgentMessage _messageFromRow(dynamic row) {
    final metadata = _metadataFromJson(row['metadata'] as String?);
    return AiAgentMessage(
      id: row['id'] as String,
      conversationId: row['conversationId'] as String,
      role: row['role'] as String,
      content: row['content'] as String,
      attachments: _attachmentsFromJson(row['attachments'] as String?),
      toolCallId: metadata['toolCallId'] as String?,
      toolCalls: _toolCallsFromMetadata(metadata),
      toolStatus: metadata['toolStatus'] as String?,
      toolResult: _toolResultFromMetadata(metadata),
      createdAt: row['createdAt'] as int,
    );
  }

  Map<String, dynamic>? _toolResultFromMetadata(Map<String, dynamic> metadata) {
    final value = metadata['toolResult'];
    if (value is! Map) return null;
    return Map<String, dynamic>.unmodifiable(
      sanitizeAiAgentValue(value) as Map<String, dynamic>,
    );
  }

  Map<String, dynamic> _metadataFromJson(String? raw) {
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : const {};
    } on FormatException {
      return const {};
    }
  }

  List<AiAgentMessageToolCall> _toolCallsFromMetadata(
    Map<String, dynamic> metadata,
  ) {
    final raw = metadata['toolCalls'];
    if (raw is! List) return const [];
    return List.unmodifiable([
      for (final item in raw)
        if (item is Map<String, dynamic> &&
            item['id'] is String &&
            item['name'] is String)
          AiAgentMessageToolCall(
            id: item['id'] as String,
            name: item['name'] as String,
            arguments: item['arguments'] is Map<String, dynamic>
                ? Map<String, dynamic>.unmodifiable(
                    item['arguments'] as Map<String, dynamic>,
                  )
                : const {},
            summary: item['summary'] is String
                ? item['summary'] as String
                : null,
          ),
    ]);
  }

  AiAgentConversation _conversationFromRow(dynamic row) => AiAgentConversation(
    id: row['id'] as String,
    targetKey: row['targetKey'] as String,
    title: row['title'] as String,
    createdAt: row['createdAt'] as int,
    updatedAt: row['updatedAt'] as int,
  );

  String _titleFromContent(String content, {bool hasAttachments = false}) {
    final normalized = content.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.isEmpty) return hasAttachments ? '图片对话' : '新对话';
    return normalized.length <= 40
        ? normalized
        : '${normalized.substring(0, 40)}...';
  }

  List<AiAgentModelConfig> _modelsFromJson(String? value) {
    if (value == null || value.isEmpty) return const [];
    try {
      final decoded = jsonDecode(value);
      if (decoded is! List) return const [];
      return [
        for (final item in decoded)
          if (item is String && item.trim().isNotEmpty)
            AiAgentModelConfig(id: item, name: item)
          else if (item is Map && item['id'] is String)
            AiAgentModelConfig(
              id: item['id'] as String,
              name: item['name'] is String
                  ? item['name'] as String
                  : item['id'] as String,
            ),
      ];
    } on FormatException {
      return const [];
    }
  }

  List<AiAgentImageAttachment> _attachmentsFromJson(String? value) {
    if (value == null || value.isEmpty) return const [];
    try {
      final decoded = jsonDecode(value);
      if (decoded is! List) return const [];
      return List.unmodifiable(
        decoded.whereType<Map<String, dynamic>>().map(
          AiAgentImageAttachment.fromJson,
        ),
      );
    } on FormatException {
      return const [];
    }
  }
}
