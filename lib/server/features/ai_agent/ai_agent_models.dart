class AiAgentModelConfig {
  final String id;
  final String name;

  const AiAgentModelConfig({required this.id, required this.name});

  Map<String, dynamic> toJson() => {'id': id, 'name': name};
}

class AiAgentSettings {
  static const defaultBaseUrl = 'https://api.openai.com/v1';
  static const defaultModel = 'gpt-4o-mini';

  final String baseUrl;
  final String model;
  final List<AiAgentModelConfig> models;
  final bool hasApiKey;

  const AiAgentSettings({
    required this.baseUrl,
    required this.model,
    required this.models,
    required this.hasApiKey,
  });

  Map<String, dynamic> toJson() => {
    'baseUrl': baseUrl,
    'model': model,
    'models': models.map((model) => model.toJson()).toList(),
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

class AiAgentImageAttachment {
  final String name;
  final String mimeType;
  final String data;

  const AiAgentImageAttachment({
    required this.name,
    required this.mimeType,
    required this.data,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'mimeType': mimeType,
    'data': data,
  };

  factory AiAgentImageAttachment.fromJson(Map<String, dynamic> json) =>
      AiAgentImageAttachment(
        name: json['name'] as String? ?? '',
        mimeType: json['mimeType'] as String,
        data: json['data'] as String,
      );
}

class AiAgentMessage {
  final String id;
  final String conversationId;
  final String role;
  final String content;
  final List<AiAgentImageAttachment> attachments;
  final int createdAt;

  const AiAgentMessage({
    required this.id,
    required this.conversationId,
    required this.role,
    required this.content,
    this.attachments = const [],
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'role': role,
    'content': content,
    'attachments': attachments
        .map((attachment) => attachment.toJson())
        .toList(),
    'createdAt': createdAt,
  };
}
