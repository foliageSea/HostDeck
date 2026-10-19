import 'dart:async';
import 'dart:convert';

import 'package:langchain/langchain.dart';

import 'package:host_deck/server/core/ssh/shared_ssh_session_resolver.dart';
import 'package:host_deck/server/core/ssh/ssh_service.dart';
import 'package:host_deck/server/features/ai_agent/ai_agent_models.dart';
import 'package:host_deck/server/features/ai_agent/ai_agent_tool_service.dart';
import 'package:host_deck/server/features/crontabs/cron_task.dart';
import 'package:host_deck/server/features/crontabs/cron_task_repository.dart';
import 'package:host_deck/server/features/crontabs/cron_task_service.dart';
import 'package:host_deck/server/features/operation_logs/operation_log_service.dart';

/// Exposes HostDeck-managed cron tasks to the AI agent.
///
/// Every mutating tool requires user approval because a scheduled command runs
/// unattended and repeatedly. Updates are full replacements so the approval
/// card always shows the complete resulting task. The target server comes from
/// the run's SSH connection, never from model-supplied arguments.
class AiAgentCronToolService implements AiAgentToolExecutor {
  static const toolNames = {
    'cron_list',
    'cron_create',
    'cron_update',
    'cron_delete',
  };
  static const maxCommandLength = 4000;
  static const maxListedTasks = 100;
  static const toolTimeout = Duration(seconds: 60);

  final AiAgentToolExecutor _delegate;
  final SshService _sshService;
  final SharedSshSessionResolver _sessionResolver;
  final CronTaskService _cronService;
  final CronTaskRepository _repository;
  final OperationLogService _operationLogs;

  AiAgentCronToolService(
    this._delegate,
    this._sshService,
    this._sessionResolver,
    this._cronService,
    this._repository,
    this._operationLogs,
  );

  static const _taskProperties = <String, dynamic>{
    'name': {
      'type': 'string',
      'description': 'Short single-line task name (max 100 characters).',
    },
    'schedule': {
      'type': 'string',
      'description':
          'Five-field cron expression (minute hour day-of-month month '
          'day-of-week) such as "0 2 * * *", or @hourly/@daily/@weekly/'
          '@monthly/@yearly/@reboot.',
    },
    'command': {
      'type': 'string',
      'description':
          'Single-line shell command run by the SSH user, unattended and '
          'repeatedly. Newlines are not allowed: for multi-step work write a '
          'script file first and schedule the script path.',
    },
    'enabled': {
      'type': 'boolean',
      'description': 'Whether the task is scheduled.',
    },
  };

  static const _specs = [
    ToolSpec(
      name: 'cron_list',
      description:
          'List the cron tasks managed by HostDeck for the connected server '
          '(not unrelated crontab entries). Call this before creating a task '
          'to avoid duplicates and before updating to get the current values.',
      inputJsonSchema: {
        'type': 'object',
        'properties': <String, dynamic>{},
        'additionalProperties': false,
      },
    ),
    ToolSpec(
      name: 'cron_create',
      description:
          'Create a scheduled cron task on the connected server. The command '
          'will run unattended on the schedule. Always requires user approval.',
      inputJsonSchema: {
        'type': 'object',
        'properties': _taskProperties,
        'required': ['name', 'schedule', 'command'],
        'additionalProperties': false,
      },
    ),
    ToolSpec(
      name: 'cron_update',
      description:
          'Replace an existing HostDeck cron task. All fields are required '
          'and overwrite the current values, so copy unchanged fields from '
          'cron_list. Always requires user approval.',
      inputJsonSchema: {
        'type': 'object',
        'properties': {
          'taskId': {'type': 'integer', 'minimum': 1},
          ..._taskProperties,
        },
        'required': ['taskId', 'name', 'schedule', 'command', 'enabled'],
        'additionalProperties': false,
      },
    ),
    ToolSpec(
      name: 'cron_delete',
      description:
          'Delete a HostDeck cron task and unschedule it. Always requires '
          'user approval.',
      inputJsonSchema: {
        'type': 'object',
        'properties': {
          'taskId': {'type': 'integer', 'minimum': 1},
        },
        'required': ['taskId'],
        'additionalProperties': false,
      },
    ),
  ];

  @override
  Future<List<ToolSpec>> resolveSpecs({bool refresh = false}) async => [
    ...await _delegate.resolveSpecs(refresh: refresh),
    ..._specs,
  ];

  @override
  bool requiresApproval(String name) => switch (name) {
    'cron_list' => false,
    _ when toolNames.contains(name) => true,
    _ => _delegate.requiresApproval(name),
  };

  @override
  String summary(String name) => switch (name) {
    'cron_list' => 'List scheduled tasks',
    'cron_create' => 'Create a scheduled task',
    'cron_update' => 'Update a scheduled task',
    'cron_delete' => 'Delete a scheduled task',
    _ => _delegate.summary(name),
  };

  @override
  Map<String, dynamic> normalizeArguments(
    String name,
    Map<String, dynamic> arguments,
  ) {
    if (!toolNames.contains(name)) {
      return _delegate.normalizeArguments(name, arguments);
    }
    final allowed = switch (name) {
      'cron_list' => const <String>{},
      'cron_delete' => const {'taskId'},
      'cron_update' => const {
        'taskId',
        'name',
        'schedule',
        'command',
        'enabled',
      },
      _ => const {'name', 'schedule', 'command', 'enabled'},
    };
    for (final key in arguments.keys) {
      if (!allowed.contains(key)) {
        throw ArgumentError('Unknown argument "$key" for $name.');
      }
    }
    if (name == 'cron_list') return const <String, dynamic>{};

    final normalized = <String, dynamic>{};
    if (name == 'cron_update' || name == 'cron_delete') {
      final taskId = arguments['taskId'];
      if (taskId is! int || taskId < 1) {
        throw ArgumentError('taskId must be a positive integer.');
      }
      normalized['taskId'] = taskId;
    }
    if (name == 'cron_delete') return Map.unmodifiable(normalized);

    for (final key in const ['name', 'schedule', 'command']) {
      final value = arguments[key];
      if (value is! String) throw ArgumentError('$key must be a string.');
      normalized[key] = value;
    }
    final enabled = arguments['enabled'];
    if (enabled == null && name == 'cron_update') {
      throw ArgumentError('enabled is required.');
    }
    if (enabled != null && enabled is! bool) {
      throw ArgumentError('enabled must be a boolean.');
    }
    normalized['enabled'] = enabled ?? true;
    if ((normalized['command'] as String).length > maxCommandLength) {
      throw ArgumentError(
        'command is longer than $maxCommandLength characters; put it in a '
        'script file and schedule the script path instead.',
      );
    }
    // Validate eagerly so the model can correct mistakes before the user is
    // asked to approve anything. serverId is a placeholder: the real one is
    // taken from the SSH connection at execution time.
    final task = _toTask(0, normalized);
    normalized
      ..['name'] = task.name
      ..['schedule'] = task.schedule
      ..['command'] = task.command;
    return Map.unmodifiable(normalized);
  }

  @override
  Future<AiAgentToolResult> execute({
    required String connectionId,
    required String targetKey,
    required String name,
    required Map<String, dynamic> arguments,
  }) async {
    if (!toolNames.contains(name)) {
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
      final serverId = _sshService.getServerId(connectionId);
      if (serverId == null) {
        _log(name, targetKey, connectionId, 'No saved server');
        return _failure(
          name,
          'Scheduled tasks require a connection to a saved server.',
        );
      }
      final outcome = await _run(
        name,
        connectionId,
        serverId,
        normalized,
      ).timeout(toolTimeout);
      _logSuccess(name, targetKey, connectionId);
      return _result(name, outcome, stopwatch.elapsedMilliseconds);
    } on _CronToolFailure catch (failure) {
      _log(name, targetKey, connectionId, failure.message);
      return _failure(name, failure.message);
    } on ArgumentError catch (error) {
      _log(name, targetKey, connectionId, 'Invalid arguments');
      return _failure(name, 'Invalid arguments: ${error.message}');
    } on StateError catch (error) {
      _log(name, targetKey, connectionId, 'Remote crontab operation failed');
      return _failure(name, _safeMessage(error.message));
    } on TimeoutException {
      _log(name, targetKey, connectionId, 'Timed out');
      return _failure(
        name,
        'The operation timed out. Check the task list before retrying.',
      );
    } catch (_) {
      _log(name, targetKey, connectionId, 'Tool execution failed');
      return _failure(name, 'Tool execution failed.');
    }
  }

  Future<_CronOutcome> _run(
    String name,
    String connectionId,
    int serverId,
    Map<String, dynamic> arguments,
  ) async {
    switch (name) {
      case 'cron_list':
        final tasks = _repository.list(serverId);
        final listed = tasks.take(maxListedTasks).map(_taskJson).toList();
        return _CronOutcome({
          'tasks': listed,
          'total': tasks.length,
          'truncated': tasks.length > maxListedTasks,
        }, changed: false);
      case 'cron_create':
        final session = await _sessionResolver.createForConnection(
          connectionId,
        );
        final created = await _cronService.create(
          session,
          _toTask(serverId, arguments),
        );
        return _CronOutcome({'task': _taskJson(created)}, changed: true);
      case 'cron_update':
        final session = await _sessionResolver.createForConnection(
          connectionId,
        );
        final taskId = arguments['taskId'] as int;
        final updated = await _cronService.update(
          session,
          taskId,
          _toTask(serverId, arguments),
        );
        if (updated == null) {
          throw const _CronToolFailure('Scheduled task not found.');
        }
        return _CronOutcome({'task': _taskJson(updated)}, changed: true);
      case 'cron_delete':
        final session = await _sessionResolver.createForConnection(
          connectionId,
        );
        final taskId = arguments['taskId'] as int;
        final deleted = await _cronService.delete(session, taskId, serverId);
        if (!deleted) {
          throw const _CronToolFailure('Scheduled task not found.');
        }
        return _CronOutcome({'success': true, 'taskId': taskId}, changed: true);
      default:
        throw ArgumentError('Unknown tool.');
    }
  }

  CronTask _toTask(int serverId, Map<String, dynamic> arguments) =>
      CronTask.fromJson({
        'serverId': serverId,
        'name': arguments['name'],
        'schedule': arguments['schedule'],
        'command': arguments['command'],
        'enabled': arguments['enabled'],
      });

  Map<String, dynamic> _taskJson(CronTask task) => {
    'id': task.id,
    'name': task.name,
    'schedule': task.schedule,
    'command': task.command,
    'enabled': task.enabled,
  };

  AiAgentToolResult _result(String name, _CronOutcome outcome, int elapsedMs) {
    final content = jsonEncode(outcome.output);
    return AiAgentToolResult(
      success: true,
      content: content,
      summary: '${summary(name)} completed',
      details: {
        'durationMs': elapsedMs,
        'truncated': outcome.output['truncated'] == true,
        'operation': switch (name) {
          'cron_list' => 'list',
          'cron_create' => 'create',
          'cron_update' => 'update',
          _ => 'delete',
        },
        'changed': outcome.changed,
        'structured': outcome.output,
      },
    );
  }

  AiAgentToolResult _failure(String name, String message) => AiAgentToolResult(
    success: false,
    content: message,
    summary: '${summary(name)} failed',
  );

  /// Remote stderr can contain paths or secrets; redact and bound it.
  String _safeMessage(String message) {
    final sanitized = sanitizeAiAgentText(message).trim();
    final bounded = sanitized.length > 500
        ? '${sanitized.substring(0, 500)}…'
        : sanitized;
    return bounded.isEmpty ? 'Remote crontab operation failed.' : bounded;
  }

  void _logSuccess(String action, String target, String connectionId) {
    _operationLogs.success(
      category: 'aiAgent',
      action: action,
      target: target,
      connectionId: connectionId,
    );
  }

  void _log(String action, String target, String connectionId, Object error) {
    _operationLogs.failure(
      category: 'aiAgent',
      action: action,
      target: target,
      connectionId: connectionId,
      error: error,
    );
  }
}

class _CronOutcome {
  final Map<String, dynamic> output;
  final bool changed;

  const _CronOutcome(this.output, {required this.changed});
}

class _CronToolFailure implements Exception {
  final String message;

  const _CronToolFailure(this.message);
}
