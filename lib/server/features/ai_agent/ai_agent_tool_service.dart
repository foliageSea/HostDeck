import 'dart:async';
import 'dart:convert';

import 'package:langchain/langchain.dart';

import 'package:host_deck/server/core/ssh/shared_ssh_session_resolver.dart';
import 'package:host_deck/server/core/ssh/ssh_service.dart';
import 'package:host_deck/server/core/ssh/ssh_session.dart';
import 'package:host_deck/server/features/agent/agent_service.dart';
import 'package:host_deck/server/features/operation_logs/operation_log_service.dart';
import 'package:host_deck/server/features/processes/process_service.dart';
import 'package:host_deck/server/features/system/monitor_service.dart';

class AiAgentToolResult {
  final bool success;
  final String content;
  final String summary;

  const AiAgentToolResult({
    required this.success,
    required this.content,
    required this.summary,
  });
}

abstract interface class AiAgentToolExecutor {
  List<ToolSpec> get specs;

  bool requiresApproval(String name);

  String summary(String name);

  Map<String, dynamic> normalizeArguments(
    String name,
    Map<String, dynamic> arguments,
  );

  Future<AiAgentToolResult> execute({
    required String connectionId,
    required String targetKey,
    required String name,
    required Map<String, dynamic> arguments,
  });
}

class AiAgentToolService implements AiAgentToolExecutor {
  static const maxOutputBytes = 64 * 1024;
  static const toolTimeout = Duration(seconds: 60);

  final AgentService _agentService;
  final MonitorService _monitorService;
  final ProcessService _processService;
  final OperationLogService _operationLogService;
  final SharedSshSessionResolver _sessionResolver;

  AiAgentToolService(
    SshService sshService,
    this._agentService,
    this._monitorService,
    this._processService,
    this._operationLogService,
  ) : _sessionResolver = SharedSshSessionResolver(
        sshService,
        type: SharedSshSessionType.sftp,
        purpose: SshSessionPurpose.aiAgent,
      );

  @override
  List<ToolSpec> get specs => const [
    ToolSpec(
      name: 'system_status',
      description:
          'Read current CPU, memory, disk, network, uptime, and OS status.',
      inputJsonSchema: {
        'type': 'object',
        'properties': <String, dynamic>{},
        'additionalProperties': false,
      },
    ),
    ToolSpec(
      name: 'process_list',
      description: 'Read the current process list sorted by CPU and memory.',
      inputJsonSchema: {
        'type': 'object',
        'properties': <String, dynamic>{},
        'additionalProperties': false,
      },
    ),
    ToolSpec(
      name: 'shell_execute',
      description:
          'Execute an arbitrary shell command. Always requires user approval.',
      inputJsonSchema: {
        'type': 'object',
        'properties': {
          'command': {'type': 'string'},
          'cwd': {'type': 'string'},
        },
        'required': ['command'],
        'additionalProperties': false,
      },
    ),
    ToolSpec(
      name: 'file_read',
      description:
          'Read a remote text file. Always requires user approval because content leaves the host.',
      inputJsonSchema: {
        'type': 'object',
        'properties': {
          'path': {'type': 'string'},
        },
        'required': ['path'],
        'additionalProperties': false,
      },
    ),
    ToolSpec(
      name: 'file_write',
      description: 'Replace a remote text file. Always requires user approval.',
      inputJsonSchema: {
        'type': 'object',
        'properties': {
          'path': {'type': 'string'},
          'content': {'type': 'string'},
        },
        'required': ['path', 'content'],
        'additionalProperties': false,
      },
    ),
    ToolSpec(
      name: 'apply_patch',
      description:
          'Apply a git patch in a remote working directory. Always requires user approval.',
      inputJsonSchema: {
        'type': 'object',
        'properties': {
          'patch': {'type': 'string'},
          'cwd': {'type': 'string'},
        },
        'required': ['patch'],
        'additionalProperties': false,
      },
    ),
  ];

  @override
  bool requiresApproval(String name) => switch (name) {
    'system_status' => false,
    _ => true,
  };

  @override
  String summary(String name) => switch (name) {
    'system_status' => 'Read system status',
    'process_list' => 'Read process list',
    'shell_execute' => 'Execute a remote shell command',
    'file_read' => 'Read a remote file',
    'file_write' => 'Write a remote file',
    'apply_patch' => 'Apply a remote patch',
    _ => 'Use unknown tool',
  };

  @override
  Map<String, dynamic> normalizeArguments(
    String name,
    Map<String, dynamic> arguments,
  ) {
    final allowedKeys = switch (name) {
      'system_status' || 'process_list' => const <String>{},
      'shell_execute' => const {'command', 'cwd'},
      'file_read' => const {'path'},
      'file_write' => const {'path', 'content'},
      'apply_patch' => const {'patch', 'cwd'},
      _ => throw ArgumentError('Unknown tool.'),
    };
    if (arguments.keys.any((key) => !allowedKeys.contains(key))) {
      throw ArgumentError('Unknown tool argument.');
    }

    return Map<String, dynamic>.unmodifiable(switch (name) {
      'system_status' || 'process_list' => const <String, dynamic>{},
      'shell_execute' => {
        'command': _boundedString(arguments, 'command'),
        'cwd': ?_strictOptionalString(arguments, 'cwd'),
      },
      'file_read' => {'path': _boundedString(arguments, 'path')},
      'file_write' => {
        'path': _boundedString(arguments, 'path'),
        'content': _boundedString(arguments, 'content'),
      },
      'apply_patch' => {
        'patch': _boundedString(arguments, 'patch'),
        'cwd': ?_strictOptionalString(arguments, 'cwd'),
      },
      _ => throw ArgumentError('Unknown tool.'),
    });
  }

  @override
  Future<AiAgentToolResult> execute({
    required String connectionId,
    required String targetKey,
    required String name,
    required Map<String, dynamic> arguments,
  }) async {
    final normalizedArguments = normalizeArguments(name, arguments);
    final action =
        const {
          'system_status',
          'process_list',
          'shell_execute',
          'file_read',
          'file_write',
          'apply_patch',
        }.contains(name)
        ? name
        : 'unknownTool';
    try {
      final session = await _sessionResolver.createForConnection(connectionId);
      final Object output = await switch (name) {
        'system_status' =>
          _monitorService
              .getSystemStatus(session)
              .then((status) => status.toJson()),
        'process_list' =>
          _processService
              .listProcesses(session)
              .then((items) => items.map((item) => item.toJson()).toList()),
        'shell_execute' => _agentService.exec(
          session,
          command: _requiredString(normalizedArguments, 'command'),
          cwd: _optionalString(normalizedArguments, 'cwd'),
          timeoutMs: toolTimeout.inMilliseconds,
          maxOutputBytes: maxOutputBytes,
        ),
        'file_read' =>
          _agentService
              .readTextFile(
                session,
                _requiredString(normalizedArguments, 'path'),
                maxBytes: maxOutputBytes,
              )
              .then((content) => {'content': content}),
        'file_write' => _writeFile(session, normalizedArguments),
        'apply_patch' => _agentService.applyPatch(
          session,
          patch: _requiredString(normalizedArguments, 'patch'),
          cwd: _optionalString(normalizedArguments, 'cwd'),
          timeoutMs: toolTimeout.inMilliseconds,
          maxOutputBytes: maxOutputBytes,
        ),
        _ => throw ArgumentError('Unknown tool.'),
      }.timeout(toolTimeout);
      final content = _limit(jsonEncode(output));
      final succeeded = _didSucceed(name, output);
      if (succeeded) {
        _operationLogService.success(
          category: 'aiAgent',
          action: action,
          target: targetKey,
          connectionId: connectionId,
        );
      } else {
        _operationLogService.failure(
          category: 'aiAgent',
          action: action,
          target: targetKey,
          connectionId: connectionId,
          error: 'Tool returned an unsuccessful result',
        );
      }
      return AiAgentToolResult(
        success: succeeded,
        content: content,
        summary: '${summary(name)} ${succeeded ? 'completed' : 'failed'}',
      );
    } catch (_) {
      _operationLogService.failure(
        category: 'aiAgent',
        action: action,
        target: targetKey,
        connectionId: connectionId,
        error: 'Tool execution failed',
      );
      return AiAgentToolResult(
        success: false,
        content: 'Tool execution failed.',
        summary: '${summary(name)} failed',
      );
    }
  }

  Future<Map<String, dynamic>> _writeFile(
    SshSession session,
    Map<String, dynamic> arguments,
  ) async {
    final path = _requiredString(arguments, 'path');
    final content = _requiredString(arguments, 'content');
    if (utf8.encode(content).length > maxOutputBytes) {
      throw ArgumentError('File content is too large.');
    }
    await _agentService.writeTextFile(session, path, content);
    return {'success': true};
  }

  String _requiredString(Map<String, dynamic> arguments, String key) {
    final value = arguments[key];
    if (value is! String || value.isEmpty) {
      throw ArgumentError('Missing required tool argument.');
    }
    return value;
  }

  String _boundedString(Map<String, dynamic> arguments, String key) {
    final value = _requiredString(arguments, key);
    if (utf8.encode(value).length > maxOutputBytes) {
      throw ArgumentError('Tool argument is too large.');
    }
    return value;
  }

  String? _optionalString(Map<String, dynamic> arguments, String key) {
    final value = arguments[key];
    return value is String && value.isNotEmpty ? value : null;
  }

  String? _strictOptionalString(Map<String, dynamic> arguments, String key) {
    if (!arguments.containsKey(key)) return null;
    final value = arguments[key];
    if (value is! String) throw ArgumentError('Invalid tool argument type.');
    if (value.isEmpty) return null;
    if (utf8.encode(value).length > maxOutputBytes) {
      throw ArgumentError('Tool argument is too large.');
    }
    return value;
  }

  bool _didSucceed(String name, Object output) {
    if (output is! Map<String, dynamic>) return true;
    return switch (name) {
      'shell_execute' => output['exitCode'] == 0,
      'apply_patch' => output['applied'] == true,
      'file_write' => output['success'] == true,
      _ => true,
    };
  }

  String _limit(String value) {
    final bytes = utf8.encode(value);
    if (bytes.length <= maxOutputBytes) return value;
    return '${utf8.decode(bytes.take(maxOutputBytes).toList(), allowMalformed: true)}\n[truncated]';
  }
}
