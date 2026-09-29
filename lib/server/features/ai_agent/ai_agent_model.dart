import 'package:langchain/langchain.dart';

import 'package:host_deck/server/features/ai_agent/ai_agent_settings_service.dart';
import 'package:host_deck/server/features/ai_agent/ai_agent_models.dart';
import 'package:host_deck/server/features/ai_agent/ai_agent_pi_bridge.dart';

class AiAgentToolCall {
  final String id;
  final String name;
  final Map<String, dynamic> arguments;

  const AiAgentToolCall({
    required this.id,
    required this.name,
    required this.arguments,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'arguments': arguments,
  };
}

class AiAgentModelMessage {
  final String role;
  final String content;
  final List<AiAgentImageAttachment> attachments;
  final String? toolCallId;
  final List<AiAgentToolCall> toolCalls;
  final Map<String, dynamic>? providerMessage;
  final bool isError;

  const AiAgentModelMessage({
    required this.role,
    required this.content,
    this.attachments = const [],
    this.toolCallId,
    this.toolCalls = const [],
    this.providerMessage,
    this.isError = false,
  });

  Map<String, dynamic> toJson() => {
    'role': role,
    'content': content,
    'attachments': attachments.map((image) => image.toJson()).toList(),
    'toolCallId': toolCallId,
    'toolCalls': toolCalls.map((call) => call.toJson()).toList(),
    'providerMessage': providerMessage,
    'isError': isError,
  };
}

class AiAgentModelResponse {
  final String text;
  final List<AiAgentToolCall> toolCalls;
  final Map<String, dynamic>? usage;
  final Map<String, dynamic>? providerMessage;

  const AiAgentModelResponse({
    required this.text,
    this.toolCalls = const [],
    this.usage,
    this.providerMessage,
  });
}

abstract interface class AiAgentModel {
  Future<AiAgentModelResponse> invoke(
    List<AiAgentModelMessage> messages,
    List<ToolSpec> tools, {
    void Function(String text)? onTextDelta,
  });
  void close();
}

abstract interface class AiAgentModelFactory {
  AiAgentModel create(AiAgentResolvedSettings settings);
}

class PiAiAgentModelFactory implements AiAgentModelFactory {
  const PiAiAgentModelFactory();

  @override
  AiAgentModel create(AiAgentResolvedSettings settings) =>
      PiAiAgentModel(settings);
}

class PiAiAgentModel implements AiAgentModel {
  final AiAgentResolvedSettings settings;
  final AiAgentPiBridge _bridge = AiAgentPiBridge();

  PiAiAgentModel(this.settings);

  @override
  Future<AiAgentModelResponse> invoke(
    List<AiAgentModelMessage> messages,
    List<ToolSpec> tools, {
    void Function(String text)? onTextDelta,
  }) async {
    final result = await _bridge.request({
      'type': 'invoke',
      'settings': {
        'provider': settings.provider,
        'api': settings.api,
        'baseUrl': settings.baseUrl,
        'model': settings.model,
        'apiKey': settings.apiKey,
        if (settings.oauthCredential != null)
          'credential': await settings.oauthCredential!(),
      },
      'messages': messages.map((message) => message.toJson()).toList(),
      'tools': tools
          .map(
            (tool) => {
              'name': tool.name,
              'description': tool.description,
              'parameters': tool.inputJsonSchema,
            },
          )
          .toList(),
    }, onTextDelta: onTextDelta);
    return AiAgentModelResponse(
      text: result['text'] as String,
      toolCalls: (result['toolCalls'] as List)
          .map(
            (value) => AiAgentToolCall(
              id: value['id'] as String,
              name: value['name'] as String,
              arguments: Map<String, dynamic>.from(value['arguments'] as Map),
            ),
          )
          .toList(),
      usage: result['usage'] as Map<String, dynamic>?,
      providerMessage: result['providerMessage'] as Map<String, dynamic>?,
    );
  }

  @override
  void close() => _bridge.close();
}
