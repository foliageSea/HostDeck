import 'package:host_deck/server/core/database/database_service.dart';

class AiAgentStoredSkill {
  final int id;
  final String name;
  final String description;
  final String content;
  final int createdAt;
  final int updatedAt;

  const AiAgentStoredSkill({
    required this.id,
    required this.name,
    required this.description,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson({bool includeContent = false}) => {
    'id': 'hostdeck:$id',
    'name': name,
    'description': description,
    'source': 'hostdeck',
    'editable': true,
    if (includeContent) 'content': content,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
  };
}

class AiAgentSkillRepository {
  final DatabaseService _database;

  AiAgentSkillRepository(this._database);

  int count() =>
      _database.db
              .select('SELECT COUNT(*) AS count FROM ai_agent_skills')
              .single['count']
          as int;

  List<AiAgentStoredSkill> list() => _database.db
      .select('''SELECT id, name, description, content, createdAt, updatedAt
          FROM ai_agent_skills ORDER BY id''')
      .map(_fromRow)
      .toList(growable: false);

  AiAgentStoredSkill? get(int id) {
    final rows = _database.db.select(
      '''SELECT id, name, description, content, createdAt, updatedAt
         FROM ai_agent_skills WHERE id = ?''',
      [id],
    );
    return rows.isEmpty ? null : _fromRow(rows.single);
  }

  AiAgentStoredSkill create({
    required String name,
    required String description,
    required String content,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    _database.db.execute(
      '''INSERT INTO ai_agent_skills (name, description, content, createdAt, updatedAt)
         VALUES (?, ?, ?, ?, ?)''',
      [name, description, content, now, now],
    );
    return get(_database.db.lastInsertRowId)!;
  }

  AiAgentStoredSkill? update(
    int id, {
    required String name,
    required String description,
    required String content,
  }) {
    _database.db.execute(
      '''UPDATE ai_agent_skills SET name = ?, description = ?, content = ?, updatedAt = ?
         WHERE id = ?''',
      [name, description, content, DateTime.now().millisecondsSinceEpoch, id],
    );
    return _database.db.updatedRows == 0 ? null : get(id);
  }

  bool delete(int id) {
    _database.db.execute('DELETE FROM ai_agent_skills WHERE id = ?', [id]);
    return _database.db.updatedRows > 0;
  }

  AiAgentStoredSkill _fromRow(dynamic row) => AiAgentStoredSkill(
    id: row['id'] as int,
    name: row['name'] as String,
    description: row['description'] as String,
    content: row['content'] as String,
    createdAt: row['createdAt'] as int,
    updatedAt: row['updatedAt'] as int,
  );
}
