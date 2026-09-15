import 'dart:async';
import 'dart:convert';

import 'package:langchain/langchain.dart';
import 'package:langchain_openai/langchain_openai.dart';

import 'package:host_deck/server/features/ai_agent/ai_agent_settings_service.dart';

class AiAgentToolCall {
  final String id;
  final String name;
  final Map<String, dynamic> arguments;

  const AiAgentToolCall({
    required this.id,
    required this.name,
    required this.arguments,
  });
}

class AiAgentModelMessage {
  final String role;
  final String content;
  final String? toolCallId;
  final List<AiAgentToolCall> toolCalls;

  const AiAgentModelMessage({
    required this.role,
    required this.content,
    this.toolCallId,
    this.toolCalls = const [],
  });
}

class AiAgentModelResponse {
  final String text;
  final List<AiAgentToolCall> toolCalls;
  final Map<String, dynamic>? usage;

  const AiAgentModelResponse({
    required this.text,
    this.toolCalls = const [],
    this.usage,
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

class LangChainOpenAiAgentModelFactory implements AiAgentModelFactory {
  const LangChainOpenAiAgentModelFactory();

  @override
  AiAgentModel create(AiAgentResolvedSettings settings) =>
      LangChainOpenAiAgentModel(settings);
}

class LangChainOpenAiAgentModel implements AiAgentModel {
  final ChatOpenAI _model;

  LangChainOpenAiAgentModel(AiAgentResolvedSettings settings)
    : _model = ChatOpenAI(
        apiKey: settings.apiKey,
        baseUrl: settings.baseUrl,
        defaultOptions: ChatOpenAIOptions(
          model: settings.model,
          temperature: 0,
          maxTokens: 4096,
          parallelToolCalls: false,
        ),
      );

  @override
  Future<AiAgentModelResponse> invoke(
    List<AiAgentModelMessage> messages,
    List<ToolSpec> tools, {
    void Function(String text)? onTextDelta,
  }) async {
    ChatResult? result;
    await for (final chunk
        in _model
            .stream(
              PromptValue.chat(messages.map(_toLangChainMessage).toList()),
              options: ChatOpenAIOptions(tools: tools),
            )
            .timeout(const Duration(minutes: 2))) {
      result = result?.concat(chunk) ?? chunk;
      final text = chunk.output.contentAsString;
      if (text.isNotEmpty) onTextDelta?.call(text);
    }
    if (result == null) {
      throw StateError('The model returned an empty response.');
    }
    return AiAgentModelResponse(
      text: result.output.contentAsString,
      toolCalls: result.output.toolCalls
          .map(
            (call) => AiAgentToolCall(
              id: call.id,
              name: call.name,
              arguments: Map<String, dynamic>.unmodifiable(call.arguments),
            ),
          )
          .toList(),
      usage: {
        'promptTokens': result.usage.promptTokens,
        'responseTokens': result.usage.responseTokens,
        'totalTokens': result.usage.totalTokens,
      },
    );
  }

  ChatMessage _toLangChainMessage(AiAgentModelMessage message) {
    return switch (message.role) {
      'system' => ChatMessage.system(message.content),
      'user' => ChatMessage.humanText(message.content),
      'assistant' => ChatMessage.aiText(
        message.content,
        toolCalls: message.toolCalls
            .map(
              (call) => AIChatMessageToolCall(
                id: call.id,
                name: call.name,
                argumentsRaw: jsonEncode(call.arguments),
                arguments: call.arguments,
              ),
            )
            .toList(),
      ),
      'tool' => ChatMessage.tool(
        toolCallId: message.toolCallId!,
        content: message.content,
      ),
      _ => throw ArgumentError('Unsupported model message role.'),
    };
  }

  @override
  void close() => _model.close();
}
