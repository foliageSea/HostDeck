import 'dart:async';
import 'dart:convert';

import 'package:langchain/langchain.dart';

import 'package:host_deck/server/core/ssh/shared_ssh_session_resolver.dart';
import 'package:host_deck/server/core/ssh/ssh_session.dart';
import 'package:host_deck/server/features/agent/agent_service.dart';
import 'package:host_deck/server/features/operation_logs/operation_log_service.dart';
import 'package:host_deck/server/features/port_forwards/port_forward_repository.dart';
import 'package:host_deck/server/features/port_forwards/port_forward_rule.dart';
import 'package:host_deck/server/features/port_forwards/port_forward_service.dart';
import 'package:host_deck/server/features/processes/process_service.dart';
import 'package:host_deck/server/features/system/monitor_service.dart';
import 'package:host_deck/server/features/ai_agent/ai_agent_models.dart';

class AiAgentToolResult {
  final bool success;
  final String content;
  final String summary;
  final Map<String, dynamic> details;

  const AiAgentToolResult({
    required this.success,
    required this.content,
    required this.summary,
    this.details = const {},
  });

  AiAgentToolResult withDetails(Map<String, dynamic> extra) =>
      AiAgentToolResult(
        success: success,
        content: content,
        summary: summary,
        details: {...details, ...extra},
      );

  Map<String, dynamic> toEventData() => {
    'content': sanitizeAiAgentText(content),
    ...sanitizeAiAgentValue(details) as Map<String, dynamic>,
  };
}

abstract interface class AiAgentToolExecutor {
  Future<List<ToolSpec>> resolveSpecs({bool refresh = false});

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
  final PortForwardRepository _portForwardRepository;
  final PortForwardService _portForwardService;
  final SharedSshSessionResolver _sessionResolver;

  AiAgentToolService(
    this._sessionResolver,
    this._agentService,
    this._monitorService,
    this._processService,
    this._operationLogService,
    this._portForwardRepository,
    this._portForwardService,
  );

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
      name: 'directory_list',
      description:
          'List files and subdirectories in a remote directory. Always requires user approval.',
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
      name: 'file_delete',
      description:
          'Delete one remote file. Directories are not deleted. Always requires user approval.',
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
      name: 'process_kill',
      description:
          'Send SIGTERM to a remote process. Always requires user approval.',
      inputJsonSchema: {
        'type': 'object',
        'properties': {
          'pid': {'type': 'integer', 'minimum': 1},
        },
        'required': ['pid'],
        'additionalProperties': false,
      },
    ),
    ToolSpec(
      name: 'port_forward_create',
      description:
          'Create and start a local SSH TCP port forward. The listener is bound to 127.0.0.1. Always requires user approval.',
      inputJsonSchema: {
        'type': 'object',
        'properties': {
          'name': {'type': 'string'},
          'localPort': {'type': 'integer', 'minimum': 1, 'maximum': 65535},
          'remoteHost': {'type': 'string'},
          'remotePort': {'type': 'integer', 'minimum': 1, 'maximum': 65535},
        },
        'required': ['name', 'localPort', 'remoteHost', 'remotePort'],
        'additionalProperties': false,
      },
    ),
    ToolSpec(
      name: 'port_forward_start',
      description:
          'Start a saved SSH local port forward for the current connection. Always requires user approval.',
      inputJsonSchema: {
        'type': 'object',
        'properties': {
          'ruleId': {'type': 'integer', 'minimum': 1},
        },
        'required': ['ruleId'],
        'additionalProperties': false,
      },
    ),
    ToolSpec(
      name: 'port_forward_list',
      description: 'List saved SSH local port forwards and their status.',
      inputJsonSchema: {
        'type': 'object',
        'properties': <String, dynamic>{},
        'additionalProperties': false,
      },
    ),
    ToolSpec(
      name: 'port_forward_status',
      description: 'Read the status of a saved SSH local port forward.',
      inputJsonSchema: {
        'type': 'object',
        'properties': {
          'ruleId': {'type': 'integer', 'minimum': 1},
        },
        'required': ['ruleId'],
        'additionalProperties': false,
      },
    ),
    ToolSpec(
      name: 'port_forward_stop',
      description:
          'Stop an SSH local port forward and release its local listener. Always requires user approval.',
      inputJsonSchema: {
        'type': 'object',
        'properties': {
          'ruleId': {'type': 'integer', 'minimum': 1},
        },
        'required': ['ruleId'],
        'additionalProperties': false,
      },
    ),
    ToolSpec(
      name: 'port_forward_delete',
      description:
          'Delete a stopped SSH local port forward rule. Always requires user approval.',
      inputJsonSchema: {
        'type': 'object',
        'properties': {
          'ruleId': {'type': 'integer', 'minimum': 1},
        },
        'required': ['ruleId'],
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
  Future<List<ToolSpec>> resolveSpecs({bool refresh = false}) async => specs;

  @override
  bool requiresApproval(String name) => switch (name) {
    'port_forward_create' => true,
    'port_forward_start' => true,
    'port_forward_list' => false,
    'port_forward_status' => false,
    'port_forward_stop' => true,
    'port_forward_delete' => true,
    'system_status' => false,
    _ => true,
  };

  @override
  String summary(String name) => switch (name) {
    'port_forward_create' => 'Create a local port forward',
    'port_forward_start' => 'Start a local port forward',
    'port_forward_list' => 'List port forwards',
    'port_forward_status' => 'Read port forward status',
    'port_forward_stop' => 'Stop a local port forward',
    'port_forward_delete' => 'Delete a port forward',
    'system_status' => 'Read system status',
    'process_list' => 'Read process list',
    'directory_list' => 'List a remote directory',
    'shell_execute' => 'Execute a remote shell command',
    'file_read' => 'Read a remote file',
    'file_write' => 'Write a remote file',
    'file_delete' => 'Delete a remote file',
    'process_kill' => 'Terminate a remote process',
    'apply_patch' => 'Apply a remote patch',
    _ => 'Use unknown tool',
  };

  @override
  Map<String, dynamic> normalizeArguments(
    String name,
    Map<String, dynamic> arguments,
  ) {
    final allowedKeys = switch (name) {
      'port_forward_create' => const {
        'name',
        'localPort',
        'remoteHost',
        'remotePort',
      },
      'port_forward_list' => const <String>{},
      'port_forward_start' ||
      'port_forward_status' ||
      'port_forward_stop' ||
      'port_forward_delete' => const {'ruleId'},
      'system_status' || 'process_list' => const <String>{},
      'directory_list' || 'file_read' || 'file_delete' => const {'path'},
      'shell_execute' => const {'command', 'cwd'},
      'file_write' => const {'path', 'content'},
      'process_kill' => const {'pid'},
      'apply_patch' => const {'patch', 'cwd'},
      _ => throw ArgumentError('Unknown tool.'),
    };
    if (arguments.keys.any((key) => !allowedKeys.contains(key))) {
      throw ArgumentError('Unknown tool argument.');
    }

    return Map<String, dynamic>.unmodifiable(switch (name) {
      'port_forward_create' => {
        'name': _boundedString(arguments, 'name'),
        'localPort': _port(arguments, 'localPort'),
        'remoteHost': _remoteHost(arguments),
        'remotePort': _port(arguments, 'remotePort'),
      },
      'port_forward_list' => const <String, dynamic>{},
      'port_forward_start' ||
      'port_forward_status' ||
      'port_forward_stop' ||
      'port_forward_delete' => {'ruleId': _positiveInt(arguments, 'ruleId')},
      'system_status' || 'process_list' => const <String, dynamic>{},
      'directory_list' ||
      'file_read' ||
      'file_delete' => {'path': _boundedString(arguments, 'path')},
      'shell_execute' => {
        'command': _boundedString(arguments, 'command'),
        'cwd': ?_strictOptionalString(arguments, 'cwd'),
      },
      'file_write' => {
        'path': _boundedString(arguments, 'path'),
        'content': _boundedString(arguments, 'content'),
      },
      'process_kill' => {'pid': _positiveInt(arguments, 'pid')},
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
          'directory_list',
          'shell_execute',
          'file_read',
          'file_write',
          'file_delete',
          'process_kill',
          'apply_patch',
          'port_forward_create',
          'port_forward_start',
          'port_forward_list',
          'port_forward_status',
          'port_forward_stop',
          'port_forward_delete',
        }.contains(name)
        ? name
        : 'unknownTool';
    final stopwatch = Stopwatch()..start();
    try {
      final Object output = await switch (name) {
        'port_forward_create' ||
        'port_forward_start' ||
        'port_forward_list' ||
        'port_forward_status' ||
        'port_forward_stop' ||
        'port_forward_delete' => _executePortForward(
          connectionId,
          name,
          normalizedArguments,
        ),
        _ => _executeRemoteTool(connectionId, name, normalizedArguments),
      }.timeout(toolTimeout);
      final elapsed = stopwatch.elapsedMilliseconds;
      final outputMap = output is Map<String, dynamic> ? output : null;
      final limited = _limitValue(jsonEncode(output));
      final displayContent = outputMap?['stdout'] is String
          ? outputMap!['stdout'] as String
          : outputMap?['content'] is String
          ? outputMap!['content'] as String
          : limited.value;
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
        content: displayContent,
        summary: '${summary(name)} ${succeeded ? 'completed' : 'failed'}',
        details: _details(
          name,
          normalizedArguments,
          outputMap,
          elapsed,
          limited.truncated || displayContent.endsWith('[truncated]'),
        ),
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

  Future<Object> _executeRemoteTool(
    String connectionId,
    String name,
    Map<String, dynamic> arguments,
  ) async {
    final session = await _sessionResolver.createForConnection(connectionId);
    return switch (name) {
      'system_status' =>
        _monitorService
            .getSystemStatus(session)
            .then((status) => status.toJson()),
      'process_list' =>
        _processService
            .listProcesses(session)
            .then((items) => items.map((item) => item.toJson()).toList()),
      'directory_list' => _listDirectory(session, arguments),
      'shell_execute' => _agentService.exec(
        session,
        command: _requiredString(arguments, 'command'),
        cwd: _optionalString(arguments, 'cwd'),
        timeoutMs: toolTimeout.inMilliseconds,
        maxOutputBytes: maxOutputBytes,
      ),
      'file_read' =>
        _agentService
            .readTextFile(
              session,
              _requiredString(arguments, 'path'),
              maxBytes: maxOutputBytes,
            )
            .then((content) => {'content': content}),
      'file_write' => _writeFile(session, arguments),
      'file_delete' => _deleteFile(session, arguments),
      'process_kill' => _killProcess(session, arguments),
      'apply_patch' => _agentService.applyPatch(
        session,
        patch: _requiredString(arguments, 'patch'),
        cwd: _optionalString(arguments, 'cwd'),
        timeoutMs: toolTimeout.inMilliseconds,
        maxOutputBytes: maxOutputBytes,
      ),
      _ => throw ArgumentError('Unknown tool.'),
    };
  }

  Future<Map<String, dynamic>> _executePortForward(
    String connectionId,
    String name,
    Map<String, dynamic> arguments,
  ) async {
    final ruleId = arguments['ruleId'] as int?;
    switch (name) {
      case 'port_forward_create':
        final rule = _portForwardRepository.addRule(
          PortForwardRule(
            name: arguments['name'] as String,
            enabled: false,
            bindHost: '127.0.0.1',
            localPort: arguments['localPort'] as int,
            remoteHost: arguments['remoteHost'] as String,
            remotePort: arguments['remotePort'] as int,
          ),
        );
        try {
          await _portForwardService.start(connectionId, rule);
          return _ruleWithStatus(rule);
        } catch (_) {
          _portForwardRepository.deleteRule(rule.id!);
          rethrow;
        }
      case 'port_forward_start':
        final rule = _requirePortForwardRule(ruleId!);
        _ensureActiveForwardBelongsToConnection(rule.id!, connectionId);
        final currentStatus = _portForwardService.statusFor(rule.id!);
        if (currentStatus['status'] != 'running') {
          await _portForwardService.start(connectionId, rule);
        }
        return _ruleWithStatus(
          _portForwardRepository.getRule(rule.id!) ?? rule,
        );
      case 'port_forward_list':
        return {
          'forwards': _portForwardRepository
              .getAllRules()
              .map(_ruleWithStatus)
              .toList(growable: false),
        };
      case 'port_forward_status':
        final rule = _requirePortForwardRule(ruleId!);
        _ensureActiveForwardBelongsToConnection(rule.id!, connectionId);
        return _ruleWithStatus(rule);
      case 'port_forward_stop':
        final rule = _requirePortForwardRule(ruleId!);
        _ensureActiveForwardBelongsToConnection(rule.id!, connectionId);
        await _portForwardService.stop(rule.id!);
        return _ruleWithStatus(
          _portForwardRepository.getRule(rule.id!) ?? rule,
        );
      case 'port_forward_delete':
        final rule = _requirePortForwardRule(ruleId!);
        _ensureActiveForwardBelongsToConnection(rule.id!, connectionId);
        final status = _portForwardService.statusFor(rule.id!);
        if (status['status'] == 'running' || status['status'] == 'error') {
          throw StateError('Stop the port forward before deleting it.');
        }
        if (!_portForwardRepository.deleteRule(rule.id!)) {
          throw StateError('Port forward rule not found.');
        }
        return {'success': true, 'ruleId': rule.id};
      default:
        throw ArgumentError('Unknown port forward tool.');
    }
  }

  PortForwardRule _requirePortForwardRule(int ruleId) {
    final rule = _portForwardRepository.getRule(ruleId);
    if (rule == null) throw StateError('Port forward rule not found.');
    return rule;
  }

  void _ensureActiveForwardBelongsToConnection(
    int ruleId,
    String connectionId,
  ) {
    final status = _portForwardService.statusFor(ruleId);
    final activeConnectionId = status['connectionId'];
    if (activeConnectionId is String && activeConnectionId != connectionId) {
      throw StateError('Port forward belongs to another connection.');
    }
  }

  Map<String, dynamic> _ruleWithStatus(PortForwardRule rule) {
    final status = _portForwardService.statusFor(rule.id ?? -1);
    return {
      ...rule.toJson(),
      ...status,
      'enabled': status['status'] == 'running',
    };
  }

  int _port(Map<String, dynamic> arguments, String key) {
    final value = arguments[key];
    if (value is! int || value < 1 || value > 65535) {
      throw ArgumentError('Port must be an integer from 1 to 65535.');
    }
    return value;
  }

  String _remoteHost(Map<String, dynamic> arguments) {
    final host = _boundedString(arguments, 'remoteHost').trim();
    if (host.isEmpty ||
        host.length > 255 ||
        host.contains(RegExp(r'[\s\x00-\x1f\x7f]'))) {
      throw ArgumentError('Invalid remote host.');
    }
    return host;
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

  Future<Map<String, dynamic>> _listDirectory(
    SshSession session,
    Map<String, dynamic> arguments,
  ) async {
    final path = _requiredString(arguments, 'path');
    final items = await _agentService.listDirectory(session, path);
    items.sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      return a.filename.toLowerCase().compareTo(b.filename.toLowerCase());
    });
    final entries = <Map<String, dynamic>>[];
    var truncated = false;
    for (final item in items) {
      if (item.filename == '.' || item.filename == '..') continue;
      if (entries.length >= 500) {
        truncated = true;
        break;
      }
      final entry = <String, dynamic>{
        'name': item.filename,
        'type': item.isDirectory ? 'directory' : 'file',
        'size': item.size,
        if (item.mtime != null) 'modifiedAt': item.mtime!.toIso8601String(),
      };
      final candidate = {
        'path': path,
        'entries': [...entries, entry],
        'truncated': false,
      };
      if (utf8.encode(jsonEncode(candidate)).length > maxOutputBytes) {
        truncated = true;
        break;
      }
      entries.add(entry);
    }
    return {'path': path, 'entries': entries, 'truncated': truncated};
  }

  Future<Map<String, dynamic>> _deleteFile(
    SshSession session,
    Map<String, dynamic> arguments,
  ) async {
    final path = _requiredString(arguments, 'path');
    await _agentService.deleteFile(session, path);
    return {'success': true, 'path': path};
  }

  Future<Map<String, dynamic>> _killProcess(
    SshSession session,
    Map<String, dynamic> arguments,
  ) async {
    final pid = _positiveInt(arguments, 'pid');
    await _processService.killProcess(session, pid);
    return {'success': true, 'pid': pid, 'signal': 'SIGTERM'};
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

  int _positiveInt(Map<String, dynamic> arguments, String key) {
    final value = arguments[key];
    if (value is! int || value <= 0) {
      throw ArgumentError('Invalid tool argument type.');
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
      'file_write' ||
      'file_delete' ||
      'process_kill' ||
      'port_forward_delete' => output['success'] == true,
      _ => true,
    };
  }

  _LimitedResult _limitValue(String value) {
    final bytes = utf8.encode(value);
    if (bytes.length <= maxOutputBytes) return _LimitedResult(value, false);
    return _LimitedResult(
      '${utf8.decode(bytes.take(maxOutputBytes).toList(), allowMalformed: true)}\n[truncated]',
      true,
    );
  }

  Map<String, dynamic> _details(
    String name,
    Map<String, dynamic> arguments,
    Map<String, dynamic>? output,
    int durationMs,
    bool truncated,
  ) {
    final result = <String, dynamic>{
      'durationMs': durationMs,
      'truncated': truncated || output?['truncated'] == true,
    };
    if (output != null) {
      for (final key in ['exitCode', 'stderr', 'stdout']) {
        if (output.containsKey(key)) result[key] = output[key];
      }
      result['structured'] = output;
    }
    final ruleId = arguments['ruleId'];
    if (ruleId is int) {
      result['ruleId'] = ruleId;
    } else if (name == 'port_forward_create' && output?['id'] is int) {
      result['ruleId'] = output!['id'];
    }
    if (name.startsWith('port_forward_')) {
      result['operation'] = switch (name) {
        'port_forward_create' => 'create',
        'port_forward_start' => 'start',
        'port_forward_list' => 'list',
        'port_forward_status' => 'status',
        'port_forward_stop' => 'stop',
        'port_forward_delete' => 'delete',
        _ => 'port-forward',
      };
      result['changed'] = switch (name) {
        'port_forward_create' ||
        'port_forward_start' ||
        'port_forward_stop' => true,
        'port_forward_delete' => output?['success'] == true,
        _ => false,
      };
    }
    final path = arguments['path'];
    if (path is String) result['path'] = path;
    final pid = arguments['pid'];
    if (pid is int) result['pid'] = pid;
    if (name == 'directory_list') result['operation'] = 'list';
    if (name == 'file_read') result['operation'] = 'read';
    if (name == 'file_write') {
      result['operation'] = 'write';
      result['changed'] = output?['success'] == true;
    }
    if (name == 'file_delete') {
      result['operation'] = 'delete';
      result['changed'] = output?['success'] == true;
    }
    if (name == 'process_kill') {
      result['operation'] = 'terminate';
      result['signal'] = 'SIGTERM';
      result['changed'] = output?['success'] == true;
    }
    if (name == 'apply_patch') {
      result['operation'] = 'patch';
      result['diff'] = arguments['patch'];
      result['changed'] = output?['applied'] == true;
    }
    return result;
  }
}

class _LimitedResult {
  final String value;
  final bool truncated;

  const _LimitedResult(this.value, this.truncated);
}
