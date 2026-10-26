import 'dart:convert';

import 'package:langchain/langchain.dart' show ToolSpec;

import 'package:host_deck/server/features/ai_agent/ai_agent_tool_service.dart';

/// Name of the built-in tool that lets the model ask the user questions.
///
/// It is handled by the run manager instead of [AiAgentToolExecutor]: the
/// answer comes from the browser, not from the connected host, so it needs the
/// run's pending-interaction machinery and never touches the SSH session.
const askUserQuestionToolName = 'ask_user_question';

const askUserQuestionSummary = 'Ask the user a question';

const _maxQuestions = 4;
const _minOptions = 2;
const _maxOptions = 6;
const _maxHeaderLength = 30;
const _maxQuestionLength = 500;
const _maxLabelLength = 100;
const _maxDescriptionLength = 300;
const _maxCustomLength = 2000;
const _recommendedSuffix = '(Recommended)';
final _idPattern = RegExp(r'^[A-Za-z0-9_-]{1,32}$');

final askUserQuestionSpec = ToolSpec(
  name: askUserQuestionToolName,
  description:
      'Ask the user one to $_maxQuestions multiple-choice questions when a '
      'required decision or missing detail cannot be found with the other '
      'tools and several reasonable options exist. Do not ask what read-only '
      'tools can discover, do not use this to request approval for a tool, '
      'and never ask for passwords or secrets. Batch related questions into '
      'one call. The user can always type a free-form answer or skip. Put '
      'the recommended option first and end its label with "(Recommended)". '
      'The result lists, per question, the chosen option labels and an '
      'optional custom answer, or status "skipped" if the user declined.',
  inputJsonSchema: {
    'type': 'object',
    'properties': {
      'questions': {
        'type': 'array',
        'minItems': 1,
        'maxItems': _maxQuestions,
        'items': {
          'type': 'object',
          'properties': {
            'id': {
              'type': 'string',
              'description':
                  'Optional stable identifier (letters, digits, _ or -).',
            },
            'header': {
              'type': 'string',
              'description': 'Short label shown above the question.',
            },
            'question': {'type': 'string'},
            'multiSelect': {
              'type': 'boolean',
              'description': 'Allow choosing more than one option.',
            },
            'options': {
              'type': 'array',
              'minItems': _minOptions,
              'maxItems': _maxOptions,
              'items': {
                'type': 'object',
                'properties': {
                  'label': {'type': 'string'},
                  'description': {'type': 'string'},
                },
                'required': ['label'],
                'additionalProperties': false,
              },
            },
          },
          'required': ['question', 'options'],
          'additionalProperties': false,
        },
      },
    },
    'required': ['questions'],
    'additionalProperties': false,
  },
);

/// Validates the arguments of an `ask_user_question` call and returns them in
/// canonical form (ids assigned, "(Recommended)" turned into a flag).
/// Throws [ArgumentError] with a message meant for the model.
Map<String, dynamic> normalizeAskUserQuestionArguments(
  Map<String, dynamic> arguments,
) {
  if (arguments.keys.any((key) => key != 'questions')) {
    throw ArgumentError('Unknown tool argument.');
  }
  final raw = arguments['questions'];
  if (raw is! List || raw.isEmpty || raw.length > _maxQuestions) {
    throw ArgumentError('questions must contain 1-$_maxQuestions items.');
  }
  final ids = <String>{};
  final questions = <Map<String, dynamic>>[];
  for (var index = 0; index < raw.length; index++) {
    final item = raw[index];
    if (item is! Map) throw ArgumentError('Each question must be an object.');
    const allowed = {'id', 'header', 'question', 'multiSelect', 'options'};
    if (item.keys.any((key) => !allowed.contains(key))) {
      throw ArgumentError('Unknown question property.');
    }
    final id = item['id'] == null ? 'q${index + 1}' : _text(item['id'], 'id');
    if (!_idPattern.hasMatch(id)) {
      throw ArgumentError('Question id must be 1-32 letters, digits, _ or -.');
    }
    if (!ids.add(id)) throw ArgumentError('Duplicate question id.');
    final question = _text(item['question'], 'question');
    if (question.isEmpty || question.length > _maxQuestionLength) {
      throw ArgumentError('question must be 1-$_maxQuestionLength characters.');
    }
    final header = item['header'] == null
        ? null
        : _text(item['header'], 'header');
    if (header != null && header.length > _maxHeaderLength) {
      throw ArgumentError(
        'header must be at most $_maxHeaderLength characters.',
      );
    }
    final multiSelect = item['multiSelect'];
    if (multiSelect != null && multiSelect is! bool) {
      throw ArgumentError('multiSelect must be a boolean.');
    }
    final rawOptions = item['options'];
    if (rawOptions is! List ||
        rawOptions.length < _minOptions ||
        rawOptions.length > _maxOptions) {
      throw ArgumentError(
        'options must contain $_minOptions-$_maxOptions items.',
      );
    }
    final labels = <String>{};
    final options = <Map<String, dynamic>>[];
    for (final option in rawOptions) {
      if (option is! Map) throw ArgumentError('Each option must be an object.');
      if (option.keys.any((key) => key != 'label' && key != 'description')) {
        throw ArgumentError('Unknown option property.');
      }
      var label = _text(option['label'], 'label');
      var recommended = false;
      if (label.endsWith(_recommendedSuffix)) {
        recommended = true;
        label = label
            .substring(0, label.length - _recommendedSuffix.length)
            .trim();
      }
      if (label.isEmpty || label.length > _maxLabelLength) {
        throw ArgumentError('label must be 1-$_maxLabelLength characters.');
      }
      if (!labels.add(label)) throw ArgumentError('Duplicate option label.');
      final description = option['description'] == null
          ? null
          : _text(option['description'], 'description');
      if (description != null && description.length > _maxDescriptionLength) {
        throw ArgumentError(
          'description must be at most $_maxDescriptionLength characters.',
        );
      }
      options.add({
        'label': label,
        if (description != null && description.isNotEmpty)
          'description': description,
        if (recommended) 'recommended': true,
      });
    }
    questions.add({
      'id': id,
      if (header != null && header.isNotEmpty) 'header': header,
      'question': question,
      'multiSelect': multiSelect == true,
      'options': options,
    });
  }
  return {'questions': questions};
}

String _text(Object? value, String name) {
  if (value is! String) throw ArgumentError('$name must be a string.');
  return value.trim();
}

/// What the user did with a pending question.
enum AiAgentQuestionStatus { answered, skipped, expired }

class AiAgentAnswer {
  final String id;
  final List<String> selected;
  final String? custom;

  const AiAgentAnswer({
    required this.id,
    this.selected = const [],
    this.custom,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'selected': selected,
    'custom': ?custom,
  };
}

/// The user's reply to a pending question: either answers or a skip.
class AiAgentQuestionReply {
  final List<AiAgentAnswer>? answers;

  const AiAgentQuestionReply.answered(List<AiAgentAnswer> this.answers);
  const AiAgentQuestionReply.skipped() : answers = null;

  bool get skipped => answers == null;
}

/// Validates browser-supplied answers against the questions that were asked.
/// Throws [ArgumentError] on any mismatch so the pending question stays open.
List<AiAgentAnswer> validateAiAgentAnswers(
  List<dynamic> questions,
  Object? raw,
) {
  if (raw is! List) throw ArgumentError('answers must be an array.');
  final byId = {
    for (final question in questions.cast<Map<String, dynamic>>())
      question['id'] as String: question,
  };
  final answered = <String, AiAgentAnswer>{};
  for (final item in raw) {
    if (item is! Map) throw ArgumentError('Each answer must be an object.');
    final id = item['id'];
    final question = id is String ? byId[id] : null;
    if (id is! String || question == null) {
      throw ArgumentError('Unknown question id.');
    }
    if (answered.containsKey(id)) throw ArgumentError('Duplicate answer.');
    final selectedRaw = item['selected'] ?? const <Object>[];
    if (selectedRaw is! List || selectedRaw.any((value) => value is! String)) {
      throw ArgumentError('selected must be an array of strings.');
    }
    final selected = selectedRaw.cast<String>();
    final labels = {
      for (final option in (question['options'] as List).cast<Map>())
        option['label'] as String,
    };
    if (selected.any((label) => !labels.contains(label)) ||
        selected.toSet().length != selected.length) {
      throw ArgumentError('selected must list distinct option labels.');
    }
    if (question['multiSelect'] != true && selected.length > 1) {
      throw ArgumentError('Only one option may be selected.');
    }
    final customRaw = item['custom'];
    if (customRaw != null && customRaw is! String) {
      throw ArgumentError('custom must be a string.');
    }
    final custom = (customRaw as String?)?.trim();
    if (custom != null && custom.length > _maxCustomLength) {
      throw ArgumentError(
        'custom must be at most $_maxCustomLength characters.',
      );
    }
    if (selected.isEmpty && (custom == null || custom.isEmpty)) continue;
    answered[id] = AiAgentAnswer(
      id: id,
      selected: selected,
      custom: custom == null || custom.isEmpty ? null : custom,
    );
  }
  // Keep the order the questions were asked in.
  return [
    for (final id in byId.keys)
      if (answered[id] != null) answered[id]!,
  ];
}

/// Builds the tool result the model receives for a finished question.
AiAgentToolResult buildQuestionResult(
  List<dynamic> questions,
  AiAgentQuestionStatus status,
  List<AiAgentAnswer> answers,
) {
  final texts = {
    for (final question in questions.cast<Map<String, dynamic>>())
      question['id'] as String: question['question'] as String,
  };
  final content = jsonEncode({
    'status': status.name,
    'answers': [
      for (final answer in answers)
        {'question': texts[answer.id], ...answer.toJson()},
    ],
    if (status == AiAgentQuestionStatus.skipped)
      'note':
          'The user skipped these questions. Proceed with a reasonable '
          'default or choose another approach.',
    if (status == AiAgentQuestionStatus.expired)
      'note': 'The user did not answer in time.',
  });
  return AiAgentToolResult(
    success: status != AiAgentQuestionStatus.expired,
    content: content,
    summary: '$askUserQuestionSummary: ${status.name}',
    details: {
      'questionStatus': status.name,
      'answers': [for (final answer in answers) answer.toJson()],
    },
  );
}
