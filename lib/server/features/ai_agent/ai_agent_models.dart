class AiAgentSettings {
  static const defaultBaseUrl = 'https://api.openai.com/v1';
  static const defaultModel = 'gpt-4o-mini';

  final String baseUrl;
  final String model;
  final bool hasApiKey;

  const AiAgentSettings({
    required this.baseUrl,
    required this.model,
    required this.hasApiKey,
  });

  Map<String, dynamic> toJson() => {
    'baseUrl': baseUrl,
    'model': model,
    'hasApiKey': hasApiKey,
  };
}

class AiAgentConversation {
  final String id;
  final String targetKey;
  final String title;
  final int createdAt;
  final int updatedAt;

  const AiAgentConversation({
    required this.id,
    required this.targetKey,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
  };
}

class AiAgentMessage {
  final String id;
  final String conversationId;
  final String role;
  final String content;
  final int createdAt;

  const AiAgentMessage({
    required this.id,
    required this.conversationId,
    required this.role,
    required this.content,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'role': role,
    'content': content,
    'createdAt': createdAt,
  };
}
