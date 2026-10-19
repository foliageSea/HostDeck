import 'dart:convert';

import 'package:langchain/langchain.dart';

import 'package:host_deck/server/features/ai_agent/ai_agent_models.dart';
import 'package:host_deck/server/features/ai_agent/ai_agent_tool_service.dart';
import 'package:host_deck/server/features/operation_logs/operation_log_repository.dart';
import 'package:host_deck/server/features/operation_logs/operation_log_service.dart';

/// Exposes HostDeck operation records to the AI agent as a read-only tool.
///
/// The tool never mutates anything and the agent cannot clear records. Only
/// audit metadata is returned (no stored detail payloads) and free text is
/// redacted and bounded before it is handed to the model.
class AiAgentOperationLogToolService implements AiAgentToolExecutor {
  static const toolName = 'operation_log_list';
  static const defaultLimit = 20;
  static const maxLimit = 50;
  static const maxFieldLength = 300;

  final AiAgentToolExecutor _delegate;
  final OperationLogRepository _repository;
  final OperationLogService _operationLogs;

  AiAgentOperationLogToolService(
    this._delegate,
    this._repository,
    this._operationLogs,
  );

  static const _statuses = ['success', 'failed'];

  static const _spec = ToolSpec(
    name: toolName,
    description:
        'List recent HostDeck operation records (audit log), newest first. '
        'Use it to check what was done recently, or why an operation '
        'failed. Read-only.',
    inputJsonSchema: {
      'type': 'object',
      'properties': {
        'limit': {
          'type': 'integer',
          'minimum': 1,
          'maximum': maxLimit,
          'description': 'Number of records to return (default $defaultLimit).',
        },
        'category': {
          'type': 'string',
          'description':
              'Optional module filter, e.g. aiAgent, agent, file, docker, '
              'process, portForward, auth, server.',
        },
        'status': {
          'type': 'string',
          'enum': _statuses,
          'description': 'Optional result filter.',
        },
        'currentConnectionOnly': {
          'type': 'boolean',
          'description':
              'Only return records of the current SSH connection '
              '(default false).',
        },
      },
      'additionalProperties': false,
    },
  );

  @override
  Future<List<ToolSpec>> resolveSpecs({bool refresh = false}) async => [
    ...await _delegate.resolveSpecs(refresh: refresh),
    _spec,
  ];

  @override
  bool requiresApproval(String name) =>
      name == toolName ? false : _delegate.requiresApproval(name);

  @override
  String summary(String name) =>
      name == toolName ? 'List operation records' : _delegate.summary(name);

  @override
  Map<String, dynamic> normalizeArguments(
    String name,
    Map<String, dynamic> arguments,
  ) {
    if (name != toolName) return _delegate.normalizeArguments(name, arguments);

    const allowed = {'limit', 'category', 'status', 'currentConnectionOnly'};
    for (final key in arguments.keys) {
      if (!allowed.contains(key)) {
        throw ArgumentError('Unknown argument "$key" for $name.');
      }
    }

    final normalized = <String, dynamic>{};
    final limit = arguments['limit'];
    if (limit != null) {
      if (limit is! int || limit < 1 || limit > maxLimit) {
        throw ArgumentError('limit must be an integer from 1 to $maxLimit.');
      }
      normalized['limit'] = limit;
    }
    final category = arguments['category'];
    if (category != null) {
      if (category is! String ||
          !RegExp(r'^[A-Za-z0-9_-]{1,50}$').hasMatch(category)) {
        throw ArgumentError('category must be a module name.');
      }
      normalized['category'] = category;
    }
    final status = arguments['status'];
    if (status != null) {
      if (status is! String || !_statuses.contains(status)) {
        throw ArgumentError('status must be "success" or "failed".');
      }
      normalized['status'] = status;
    }
    final currentOnly = arguments['currentConnectionOnly'];
    if (currentOnly != null) {
      if (currentOnly is! bool) {
        throw ArgumentError('currentConnectionOnly must be a boolean.');
      }
      normalized['currentConnectionOnly'] = currentOnly;
    }
    return Map.unmodifiable(normalized);
  }

  @override
  Future<AiAgentToolResult> execute({
    required String connectionId,
    required String targetKey,
    required String name,
    required Map<String, dynamic> arguments,
  }) async {
    if (name != toolName) {
      return _delegate.execute(
        connectionId: connectionId,
        targetKey: targetKey,
        name: name,
        arguments: arguments,
      );
    }

    final stopwatch = Stopwatch()..start();
    try {
      final normalized = normalizeArguments(name, arguments);
      final limit = normalized['limit'] as int? ?? defaultLimit;
      // Read before recording this call so the result is not polluted by it.
      final logs = _repository.list(
        limit: limit,
        category: normalized['category'] as String?,
        status: normalized['status'] as String?,
        connectionId: normalized['currentConnectionOnly'] == true
            ? connectionId
            : null,
      );
      final records = [
        for (final log in logs)
          {
            'id': log.id,
            'time': DateTime.fromMillisecondsSinceEpoch(
              log.createdAt,
            ).toIso8601String(),
            'category': log.category,
            'action': log.action,
            'status': log.status,
            'target': ?_safe(log.target),
            'error': ?_safe(log.errorMessage),
            'currentConnection': log.connectionId == connectionId,
          },
      ];
      final output = {'records': records, 'count': records.length};
      _operationLogs.success(
        category: 'aiAgent',
        action: toolName,
        target: targetKey,
        connectionId: connectionId,
      );
      return AiAgentToolResult(
        success: true,
        content: jsonEncode(output),
        summary: '${summary(name)} completed',
        details: {
          'durationMs': stopwatch.elapsedMilliseconds,
          'truncated': false,
          'operation': 'list',
          'changed': false,
          'structured': output,
        },
      );
    } on ArgumentError catch (error) {
      _fail(targetKey, connectionId, 'Invalid arguments');
      return _failure(name, 'Invalid arguments: ${error.message}');
    } catch (_) {
      _fail(targetKey, connectionId, 'Tool execution failed');
      return _failure(name, 'Tool execution failed.');
    }
  }

  String? _safe(String? value) {
    if (value == null || value.isEmpty) return null;
    final sanitized = sanitizeAiAgentText(value);
    return sanitized.length > maxFieldLength
        ? '${sanitized.substring(0, maxFieldLength)}…'
        : sanitized;
  }

  AiAgentToolResult _failure(String name, String message) => AiAgentToolResult(
    success: false,
    content: message,
    summary: '${summary(name)} failed',
  );

  void _fail(String target, String connectionId, Object error) {
    _operationLogs.failure(
      category: 'aiAgent',
      action: toolName,
      target: target,
      connectionId: connectionId,
      error: error,
    );
  }
}
