import 'dart:convert';

import 'package:shelf/shelf.dart';

import 'package:host_deck/server/core/http/result.dart';
import 'package:host_deck/server/core/ssh/shared_ssh_session_resolver.dart';
import 'package:host_deck/server/core/ssh/ssh_service.dart';
import 'package:host_deck/server/core/ssh/ssh_session.dart';
import 'package:host_deck/server/features/agent/agent_service.dart';
import 'package:host_deck/server/features/operation_logs/operation_log_service.dart';

class AgentController {
  final AgentService _agentService;
  final OperationLogService _operationLogService;
  final SharedSshSessionResolver _sessionResolver;
  final SshService _sshService;

  AgentController(
    this._sshService,
    this._agentService,
    this._operationLogService,
  ) : _sessionResolver = SharedSshSessionResolver(
        _sshService,
        type: SharedSshSessionType.sftp,
      );

  Future<Response> exec(Request request) async {
    final data = await _readJson(request);
    final command = _requiredString(data, 'command');

    if (command == null) {
      return Result.fail(400, 'Missing command');
    }

    return _withSession(request, data, (session) async {
      try {
        final result = await _agentService.exec(
          session,
          command: command,
          cwd: _optionalString(data, 'cwd'),
          timeoutMs: _optionalInt(data, 'timeoutMs'),
          stdin: _optionalString(data, 'stdin'),
          maxOutputBytes: _optionalInt(data, 'maxOutputBytes'),
        );
        _recordSuccess('exec', command, session.connectionId);
        return Result.ok(result);
      } catch (e) {
        _recordFailure('exec', command, session.connectionId, e);
        return Result.fail(500, e.toString());
      }
    });
  }

  Future<Response> readFile(Request request) async {
    final data = await _readJson(request);
    final path = _requiredString(data, 'path');
    if (path == null) {
      return Result.fail(400, 'Missing path');
    }

    return _withSession(request, data, (session) async {
      try {
        final content = await _agentService.readTextFile(session, path);
        _recordSuccess('read', path, session.connectionId);
        return Result.ok({'path': path, 'content': content});
      } catch (e) {
        _recordFailure('read', path, session.connectionId, e);
        return Result.fail(500, e.toString());
      }
    });
  }

  Future<Response> writeFile(Request request) async {
    final data = await _readJson(request);
    final path = _requiredString(data, 'path');
    final content = _requiredString(data, 'content');

    if (path == null) {
      return Result.fail(400, 'Missing path');
    }
    if (content == null) {
      return Result.fail(400, 'Missing content');
    }

    return _withSession(request, data, (session) async {
      try {
        await _agentService.writeTextFile(session, path, content);
        _recordSuccess('write', path, session.connectionId);
        return Result.ok({'path': path, 'success': true});
      } catch (e) {
        _recordFailure('write', path, session.connectionId, e);
        return Result.fail(500, e.toString());
      }
    });
  }

  Future<Response> applyPatch(Request request) async {
    final data = await _readJson(request);
    final patch = _requiredString(data, 'patch');

    if (patch == null) {
      return Result.fail(400, 'Missing patch');
    }

    return _withSession(request, data, (session) async {
      try {
        final result = await _agentService.applyPatch(
          session,
          patch: patch,
          cwd: _optionalString(data, 'cwd'),
          timeoutMs: _optionalInt(data, 'timeoutMs'),
        );
        _recordSuccess(
          'patch',
          _optionalString(data, 'cwd'),
          session.connectionId,
        );
        return Result.ok(result);
      } catch (e) {
        _recordFailure(
          'patch',
          _optionalString(data, 'cwd'),
          session.connectionId,
          e,
        );
        return Result.fail(500, e.toString());
      }
    });
  }

  Future<Response> _withSession(
    Request request,
    Map<String, dynamic> data,
    Future<Response> Function(SshSession session) action,
  ) async {
    final connectionId =
        _optionalString(data, 'connectionId') ??
        request.url.queryParameters['connectionId'];
    final sessionId =
        _optionalString(data, 'sessionId') ??
        request.url.queryParameters['sessionId'];

    try {
      final session = await _resolveSession(connectionId, sessionId);
      return action(session);
    } catch (error) {
      return _sessionResolver.errorResponse(error);
    }
  }

  Future<SshSession> _resolveSession(
    String? connectionId,
    String? sessionId,
  ) async {
    if (sessionId != null) {
      final session = _sshService.getSession(sessionId);
      if (session != null) {
        return session;
      }
      throw StateError('Session not found');
    }

    if (connectionId == null || connectionId.isEmpty) {
      throw ArgumentError('Missing connectionId or sessionId');
    }

    return _sessionResolver.createForConnection(connectionId);
  }

  Future<Map<String, dynamic>> _readJson(Request request) async {
    final body = await request.readAsString();
    if (body.trim().isEmpty) {
      return {};
    }

    final data = jsonDecode(body);
    if (data is Map<String, dynamic>) {
      return data;
    }
    return {};
  }

  String? _requiredString(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value is String && value.isNotEmpty) {
      return value;
    }
    return null;
  }

  String? _optionalString(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value is String && value.isNotEmpty) {
      return value;
    }
    return null;
  }

  int? _optionalInt(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value is int) {
      return value;
    }
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }

  void _recordSuccess(String action, String? target, String connectionId) {
    _operationLogService.success(
      category: 'agent',
      action: action,
      target: target,
      connectionId: connectionId,
    );
  }

  void _recordFailure(
    String action,
    String? target,
    String connectionId,
    Object error,
  ) {
    _operationLogService.failure(
      category: 'agent',
      action: action,
      target: target,
      connectionId: connectionId,
      error: error,
    );
  }
}
