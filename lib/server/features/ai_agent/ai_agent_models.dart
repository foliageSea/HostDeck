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
  final bool showRemoteSkills;

  const AiAgentSettings({
    required this.baseUrl,
    required this.model,
    required this.models,
    required this.hasApiKey,
    required this.showRemoteSkills,
  });

  Map<String, dynamic> toJson() => {
    'baseUrl': baseUrl,
    'model': model,
    'models': models.map((model) => model.toJson()).toList(),
    'hasApiKey': hasApiKey,
    'showRemoteSkills': showRemoteSkills,
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

class AiAgentMessageToolCall {
  final String id;
  final String name;
  final Map<String, dynamic> arguments;
  final String? summary;

  const AiAgentMessageToolCall({
    required this.id,
    required this.name,
    this.arguments = const {},
    this.summary,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'arguments': arguments,
    if (summary != null) 'summary': summary,
  };
}

class AiAgentMessage {
  final String id;
  final String conversationId;
  final String role;
  final String content;
  final List<AiAgentImageAttachment> attachments;
  final String? toolCallId;
  final List<AiAgentMessageToolCall> toolCalls;
  final String? toolStatus;
  final int createdAt;

  const AiAgentMessage({
    required this.id,
    required this.conversationId,
    required this.role,
    required this.content,
    this.attachments = const [],
    this.toolCallId,
    this.toolCalls = const [],
    this.toolStatus,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'role': role,
    'content': content,
    'attachments': attachments
        .map((attachment) => attachment.toJson())
        .toList(),
    if (toolCallId != null) 'toolCallId': toolCallId,
    if (toolCalls.isNotEmpty)
      'toolCalls': toolCalls.map((call) => call.toJson()).toList(),
    if (toolStatus != null) 'toolStatus': toolStatus,
    'createdAt': createdAt,
  };
}

enum AiAgentRunStepType { model, tool, approval, message, error, summary }

enum AiAgentRunStepStatus {
  queued,
  running,
  waitingApproval,
  success,
  failed,
  rejected,
  cancelled,
  expired,
}

class AiAgentRunStep {
  final String runId;
  final String stepId;
  final String? parentStepId;
  final int sequence;
  final AiAgentRunStepType type;
  final AiAgentRunStepStatus status;
  final int startedAt;
  final int? completedAt;

  const AiAgentRunStep({
    required this.runId,
    required this.stepId,
    this.parentStepId,
    required this.sequence,
    required this.type,
    required this.status,
    required this.startedAt,
    this.completedAt,
  });

  Map<String, dynamic> toJson() => {
    'runId': runId,
    'stepId': stepId,
    if (parentStepId != null) 'parentStepId': parentStepId,
    'sequence': sequence,
    'type': type.name,
    'status': status.name == 'waitingApproval'
        ? 'waiting-approval'
        : status.name,
    'startedAt': startedAt,
    if (completedAt != null) 'completedAt': completedAt,
  };
}

class AiAgentToolCallRecord {
  final String callId;
  final String stepId;
  final String name;
  final Map<String, dynamic> arguments;
  final String summary;
  final AiAgentRunStepStatus status;

  const AiAgentToolCallRecord({
    required this.callId,
    required this.stepId,
    required this.name,
    required this.arguments,
    required this.summary,
    required this.status,
  });

  Map<String, dynamic> toJson() => {
    'callId': callId,
    'stepId': stepId,
    'name': name,
    'arguments': arguments,
    'summary': summary,
    'status': status.name == 'waitingApproval'
        ? 'waiting-approval'
        : status.name,
  };
}

final _sensitiveKey = RegExp(
  r'(password|passwd|token|secret|api[_-]?key|authorization|private[_-]?key|cookie)',
  caseSensitive: false,
);
final _sensitiveText = RegExp(
  r'(bearer\s+)[^\s,;]+|((?:password|passwd|token|secret|api[_-]?key|authorization)\s*[:=]\s*)(?:bearer\s+)?[^\s,;]+',
  caseSensitive: false,
);

String sanitizeAiAgentText(String value) => value.replaceAllMapped(
  _sensitiveText,
  (match) => match.group(1) ?? '${match.group(2)}[redacted]',
);

Object? sanitizeAiAgentValue(Object? value, {String? key}) {
  if (key != null && _sensitiveKey.hasMatch(key)) return '[redacted]';
  if (value is String) return sanitizeAiAgentText(value);
  if (value is Map) {
    return <String, dynamic>{
      for (final entry in value.entries)
        entry.key.toString(): sanitizeAiAgentValue(
          entry.value,
          key: entry.key.toString(),
        ),
    };
  }
  if (value is List) {
    return value.map((item) => sanitizeAiAgentValue(item)).toList();
  }
  return value;
}
