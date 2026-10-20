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

typedef _ToolHandler =
    Future<Object> Function(String connectionId, Map<String, dynamic> args);

/// Extra, tool-specific fields for the `details` of a tool result.
typedef _ToolDetails =
    Map<String, dynamic> Function(
      Map<String, dynamic> arguments,
      Map<String, dynamic>? output,
    );

/// Everything the service knows about one tool, in one place: its schema,
/// whether it needs approval, how arguments are validated, how it runs, and
/// how its result is interpreted. Adding a tool means adding one entry to
/// [AiAgentToolService._definitions].
class _ToolDefinition {
  final ToolSpec spec;
  final String summary;

  /// Safe default: everything needs approval unless explicitly read-only.
  final bool requiresApproval;
  final Map<String, dynamic> Function(Map<String, dynamic> arguments) normalize;
  final _ToolHandler run;

  /// Decides whether a structured output counts as success. Defaults to true.
  final bool Function(Map<String, dynamic> output)? succeeded;
  final _ToolDetails? details;

  _ToolDefinition({
    required String name,
    required String description,
    required this.summary,
    required this.normalize,
    required this.run,
    Map<String, dynamic> properties = const {},
    List<String> required = const [],
    this.requiresApproval = true,
    this.succeeded,
    this.details,
  }) : spec = ToolSpec(
         name: name,
         description: description,
         inputJsonSchema: {
           'type': 'object',
           'properties': properties,
           if (required.isNotEmpty) 'required': required,
           'additionalProperties': false,
         },
       );

  Set<String> get allowedArguments =>
      (spec.inputJsonSchema['properties'] as Map).keys.cast<String>().toSet();
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

  late final Map<String, _ToolDefinition> _tools = {
    for (final tool in _definitions()) tool.spec.name: tool,
  };

  AiAgentToolService(
    this._sessionResolver,
    this._agentService,
    this._monitorService,
    this._processService,
    this._operationLogService,
    this._portForwardRepository,
    this._portForwardService,
  );

  List<ToolSpec> get specs => [for (final tool in _tools.values) tool.spec];

  List<_ToolDefinition> _definitions() => [
    _ToolDefinition(
      name: 'system_status',
      description:
          'Read current CPU, memory, disk, network, uptime, and OS status.',
      summary: 'Read system status',
      requiresApproval: false,
      normalize: _noArguments,
      run: _withSession(
        (session, _) => _monitorService
            .getSystemStatus(session)
            .then((status) => status.toJson()),
      ),
    ),
    _ToolDefinition(
      name: 'process_list',
      description: 'Read the current process list sorted by CPU and memory.',
      summary: 'Read process list',
      normalize: _noArguments,
      run: _withSession(
        (session, _) => _processService
            .listProcesses(session)
            .then((items) => items.map((item) => item.toJson()).toList()),
      ),
    ),
    _ToolDefinition(
      name: 'directory_list',
      description:
          'List files and subdirectories in a remote directory. Always requires user approval.',
      summary: 'List a remote directory',
      properties: {
        'path': {'type': 'string'},
      },
      required: ['path'],
      normalize: _pathOnly,
      run: _withSession(_listDirectory),
      details: (_, _) => {'operation': 'list'},
    ),
    _ToolDefinition(
      name: 'shell_execute',
      description:
          'Execute an arbitrary shell command. Always requires user approval.',
      summary: 'Execute a remote shell command',
      properties: {
        'command': {'type': 'string'},
        'cwd': {'type': 'string'},
      },
      required: ['command'],
      normalize: (arguments) => {
        'command': _boundedString(arguments, 'command'),
        'cwd': ?_strictOptionalString(arguments, 'cwd'),
      },
      run: _withSession(
        (session, arguments) => _agentService.exec(
          session,
          command: _requiredString(arguments, 'command'),
          cwd: _optionalString(arguments, 'cwd'),
          timeoutMs: toolTimeout.inMilliseconds,
          maxOutputBytes: maxOutputBytes,
        ),
      ),
      succeeded: (output) => output['exitCode'] == 0,
    ),
    _ToolDefinition(
      name: 'file_read',
      description:
          'Read a remote text file. Always requires user approval because content leaves the host.',
      summary: 'Read a remote file',
      properties: {
        'path': {'type': 'string'},
      },
      required: ['path'],
      normalize: _pathOnly,
      run: _withSession(
        (session, arguments) => _agentService
            .readTextFile(
              session,
              _requiredString(arguments, 'path'),
              maxBytes: maxOutputBytes,
            )
            .then((content) => {'content': content}),
      ),
      details: (_, _) => {'operation': 'read'},
    ),
    _ToolDefinition(
      name: 'file_write',
      description: 'Replace a remote text file. Always requires user approval.',
      summary: 'Write a remote file',
      properties: {
        'path': {'type': 'string'},
        'content': {'type': 'string'},
      },
      required: ['path', 'content'],
      normalize: (arguments) => {
        'path': _boundedString(arguments, 'path'),
        'content': _boundedString(arguments, 'content'),
      },
      run: _withSession(_writeFile),
      succeeded: _reportedSuccess,
      details: (_, output) => {
        'operation': 'write',
        'changed': output?['success'] == true,
      },
    ),
    _ToolDefinition(
      name: 'file_delete',
      description:
          'Delete one remote file. Directories are not deleted. Always requires user approval.',
      summary: 'Delete a remote file',
      properties: {
        'path': {'type': 'string'},
      },
      required: ['path'],
      normalize: _pathOnly,
      run: _withSession(_deleteFile),
      succeeded: _reportedSuccess,
      details: (_, output) => {
        'operation': 'delete',
        'changed': output?['success'] == true,
      },
    ),
    _ToolDefinition(
      name: 'process_kill',
      description:
          'Send SIGTERM to a remote process. Always requires user approval.',
      summary: 'Terminate a remote process',
      properties: {
        'pid': {'type': 'integer', 'minimum': 1},
      },
      required: ['pid'],
      normalize: (arguments) => {'pid': _positiveInt(arguments, 'pid')},
      run: _withSession(_killProcess),
      succeeded: _reportedSuccess,
      details: (_, output) => {
        'operation': 'terminate',
        'signal': 'SIGTERM',
        'changed': output?['success'] == true,
      },
    ),
    _ToolDefinition(
      name: 'port_forward_create',
      description:
          'Create and start a local SSH TCP port forward. The listener is bound to 127.0.0.1. Always requires user approval.',
      summary: 'Create a local port forward',
      properties: {
        'name': {'type': 'string'},
        'localPort': {'type': 'integer', 'minimum': 1, 'maximum': 65535},
        'remoteHost': {'type': 'string'},
        'remotePort': {'type': 'integer', 'minimum': 1, 'maximum': 65535},
      },
      required: ['name', 'localPort', 'remoteHost', 'remotePort'],
      normalize: (arguments) => {
        'name': _boundedString(arguments, 'name'),
        'localPort': _port(arguments, 'localPort'),
        'remoteHost': _remoteHost(arguments),
        'remotePort': _port(arguments, 'remotePort'),
      },
      run: _createPortForward,
      details: (_, output) => {
        'operation': 'create',
        'changed': true,
        if (output?['id'] is int) 'ruleId': output!['id'],
      },
    ),
    _ToolDefinition(
      name: 'port_forward_start',
      description:
          'Start a saved SSH local port forward for the current connection. Always requires user approval.',
      summary: 'Start a local port forward',
      properties: _ruleIdProperties,
      required: ['ruleId'],
      normalize: _ruleIdOnly,
      run: _startPortForward,
      details: (_, _) => {'operation': 'start', 'changed': true},
    ),
    _ToolDefinition(
      name: 'port_forward_list',
      description: 'List saved SSH local port forwards and their status.',
      summary: 'List port forwards',
      requiresApproval: false,
      normalize: _noArguments,
      run: _listPortForwards,
      details: (_, _) => {'operation': 'list', 'changed': false},
    ),
    _ToolDefinition(
      name: 'port_forward_status',
      description: 'Read the status of a saved SSH local port forward.',
      summary: 'Read port forward status',
      requiresApproval: false,
      properties: _ruleIdProperties,
      required: ['ruleId'],
      normalize: _ruleIdOnly,
      run: _portForwardStatus,
      details: (_, _) => {'operation': 'status', 'changed': false},
    ),
    _ToolDefinition(
      name: 'port_forward_stop',
      description:
          'Stop an SSH local port forward and release its local listener. Always requires user approval.',
      summary: 'Stop a local port forward',
      properties: _ruleIdProperties,
      required: ['ruleId'],
      normalize: _ruleIdOnly,
      run: _stopPortForward,
      details: (_, _) => {'operation': 'stop', 'changed': true},
    ),
    _ToolDefinition(
      name: 'port_forward_delete',
      description:
          'Delete a stopped SSH local port forward rule. Always requires user approval.',
      summary: 'Delete a port forward',
      properties: _ruleIdProperties,
      required: ['ruleId'],
      normalize: _ruleIdOnly,
      run: _deletePortForward,
      succeeded: _reportedSuccess,
      details: (_, output) => {
        'operation': 'delete',
        'changed': output?['success'] == true,
      },
    ),
    _ToolDefinition(
      name: 'apply_patch',
      description:
          'Apply a git patch in a remote working directory. Always requires user approval.',
      summary: 'Apply a remote patch',
      properties: {
        'patch': {'type': 'string'},
        'cwd': {'type': 'string'},
      },
      required: ['patch'],
      normalize: (arguments) => {
        'patch': _boundedString(arguments, 'patch'),
        'cwd': ?_strictOptionalString(arguments, 'cwd'),
      },
      run: _withSession(
        (session, arguments) => _agentService.applyPatch(
          session,
          patch: _requiredString(arguments, 'patch'),
          cwd: _optionalString(arguments, 'cwd'),
          timeoutMs: toolTimeout.inMilliseconds,
          maxOutputBytes: maxOutputBytes,
        ),
      ),
      succeeded: (output) => output['applied'] == true,
      details: (arguments, output) => {
        'operation': 'patch',
        'diff': arguments['patch'],
        'changed': output?['applied'] == true,
      },
    ),
  ];

  static const _ruleIdProperties = <String, dynamic>{
    'ruleId': {'type': 'integer', 'minimum': 1},
  };

  @override
  Future<List<ToolSpec>> resolveSpecs({bool refresh = false}) async => specs;

  @override
  bool requiresApproval(String name) => _tools[name]?.requiresApproval ?? true;

  @override
  String summary(String name) => _tools[name]?.summary ?? 'Use unknown tool';

  @override
  Map<String, dynamic> normalizeArguments(
    String name,
    Map<String, dynamic> arguments,
  ) {
    final tool = _tools[name] ?? (throw ArgumentError('Unknown tool.'));
    final allowed = tool.allowedArguments;
    if (arguments.keys.any((key) => !allowed.contains(key))) {
      throw ArgumentError('Unknown tool argument.');
    }
    return Map<String, dynamic>.unmodifiable(tool.normalize(arguments));
  }

  @override
  Future<AiAgentToolResult> execute({
    required String connectionId,
    required String targetKey,
    required String name,
    required Map<String, dynamic> arguments,
  }) async {
    final normalizedArguments = normalizeArguments(name, arguments);
    final tool = _tools[name]!;
    final stopwatch = Stopwatch()..start();
    try {
      final output = await tool
          .run(connectionId, normalizedArguments)
          .timeout(toolTimeout);
      final elapsed = stopwatch.elapsedMilliseconds;
      final outputMap = output is Map<String, dynamic> ? output : null;
      final limited = _limitValue(jsonEncode(output));
      final displayContent = outputMap?['stdout'] is String
          ? outputMap!['stdout'] as String
          : outputMap?['content'] is String
          ? outputMap!['content'] as String
          : limited.value;
      final succeeded =
          outputMap == null || (tool.succeeded?.call(outputMap) ?? true);
      if (succeeded) {
        _operationLogService.success(
          category: 'aiAgent',
          action: name,
          target: targetKey,
          connectionId: connectionId,
        );
      } else {
        _operationLogService.failure(
          category: 'aiAgent',
          action: name,
          target: targetKey,
          connectionId: connectionId,
          error: 'Tool returned an unsuccessful result',
        );
      }
      return AiAgentToolResult(
        success: succeeded,
        content: displayContent,
        summary: '${tool.summary} ${succeeded ? 'completed' : 'failed'}',
        details: _details(
          tool,
          normalizedArguments,
          outputMap,
          elapsed,
          limited.truncated || displayContent.endsWith('[truncated]'),
        ),
      );
    } catch (_) {
      _operationLogService.failure(
        category: 'aiAgent',
        action: name,
        target: targetKey,
        connectionId: connectionId,
        error: 'Tool execution failed',
      );
      return AiAgentToolResult(
        success: false,
        content: 'Tool execution failed.',
        summary: '${tool.summary} failed',
      );
    }
  }

  // --- handlers -----------------------------------------------------------

  /// Adapts a handler that needs an SSH session to the common signature.
  _ToolHandler _withSession(
    Future<Object> Function(SshSession session, Map<String, dynamic> arguments)
    body,
  ) =>
      (connectionId, arguments) async => body(
        await _sessionResolver.createForConnection(connectionId),
        arguments,
      );

  Future<Map<String, dynamic>> _createPortForward(
    String connectionId,
    Map<String, dynamic> arguments,
  ) async {
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
  }

  Future<Map<String, dynamic>> _startPortForward(
    String connectionId,
    Map<String, dynamic> arguments,
  ) async {
    final rule = _ownedPortForwardRule(arguments, connectionId);
    final currentStatus = _portForwardService.statusFor(rule.id!);
    if (currentStatus['status'] != 'running') {
      await _portForwardService.start(connectionId, rule);
    }
    return _ruleWithStatus(_portForwardRepository.getRule(rule.id!) ?? rule);
  }

  Future<Map<String, dynamic>> _listPortForwards(
    String connectionId,
    Map<String, dynamic> arguments,
  ) async => {
    'forwards': _portForwardRepository
        .getAllRules()
        .map(_ruleWithStatus)
        .toList(growable: false),
  };

  Future<Map<String, dynamic>> _portForwardStatus(
    String connectionId,
    Map<String, dynamic> arguments,
  ) async => _ruleWithStatus(_ownedPortForwardRule(arguments, connectionId));

  Future<Map<String, dynamic>> _stopPortForward(
    String connectionId,
    Map<String, dynamic> arguments,
  ) async {
    final rule = _ownedPortForwardRule(arguments, connectionId);
    await _portForwardService.stop(rule.id!);
    return _ruleWithStatus(_portForwardRepository.getRule(rule.id!) ?? rule);
  }

  Future<Map<String, dynamic>> _deletePortForward(
    String connectionId,
    Map<String, dynamic> arguments,
  ) async {
    final rule = _ownedPortForwardRule(arguments, connectionId);
    final status = _portForwardService.statusFor(rule.id!);
    if (status['status'] == 'running' || status['status'] == 'error') {
      throw StateError('Stop the port forward before deleting it.');
    }
    if (!_portForwardRepository.deleteRule(rule.id!)) {
      throw StateError('Port forward rule not found.');
    }
    return {'success': true, 'ruleId': rule.id};
  }

  /// Loads the rule named by `ruleId` and ensures it is not active on
  /// another connection.
  PortForwardRule _ownedPortForwardRule(
    Map<String, dynamic> arguments,
    String connectionId,
  ) {
    final rule = _portForwardRepository.getRule(arguments['ruleId'] as int);
    if (rule == null) throw StateError('Port forward rule not found.');
    final status = _portForwardService.statusFor(rule.id!);
    final activeConnectionId = status['connectionId'];
    if (activeConnectionId is String && activeConnectionId != connectionId) {
      throw StateError('Port forward belongs to another connection.');
    }
    return rule;
  }

  Map<String, dynamic> _ruleWithStatus(PortForwardRule rule) {
    final status = _portForwardService.statusFor(rule.id ?? -1);
    return {
      ...rule.toJson(),
      ...status,
      'enabled': status['status'] == 'running',
    };
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

  // --- argument validation ------------------------------------------------

  static Map<String, dynamic> _noArguments(Map<String, dynamic> arguments) =>
      const {};

  Map<String, dynamic> _pathOnly(Map<String, dynamic> arguments) => {
    'path': _boundedString(arguments, 'path'),
  };

  Map<String, dynamic> _ruleIdOnly(Map<String, dynamic> arguments) => {
    'ruleId': _positiveInt(arguments, 'ruleId'),
  };

  static bool _reportedSuccess(Map<String, dynamic> output) =>
      output['success'] == true;

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

  // --- result shaping -----------------------------------------------------

  _LimitedResult _limitValue(String value) {
    final bytes = utf8.encode(value);
    if (bytes.length <= maxOutputBytes) return _LimitedResult(value, false);
    return _LimitedResult(
      '${utf8.decode(bytes.take(maxOutputBytes).toList(), allowMalformed: true)}\n[truncated]',
      true,
    );
  }

  Map<String, dynamic> _details(
    _ToolDefinition tool,
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
    if (ruleId is int) result['ruleId'] = ruleId;
    final path = arguments['path'];
    if (path is String) result['path'] = path;
    final pid = arguments['pid'];
    if (pid is int) result['pid'] = pid;
    result.addAll(tool.details?.call(arguments, output) ?? const {});
    return result;
  }
}

class _LimitedResult {
  final String value;
  final bool truncated;

  const _LimitedResult(this.value, this.truncated);
}
