import 'package:shelf/shelf.dart';

import 'package:host_deck/server/core/http/result.dart';
import 'package:host_deck/server/core/ssh/ssh_service.dart';
import 'package:host_deck/server/core/ssh/ssh_session.dart';

enum SharedSshSessionType { shell, sftp }

class SharedSshSessionResolver {
  final SshService _sshService;
  final SharedSshSessionType _type;
  final Map<String, String> _sharedSessionIds = {};
  final Map<String, Future<SshSession>> _pendingSharedSessions = {};

  SharedSshSessionResolver(
    this._sshService, {
    required SharedSshSessionType type,
  }) : _type = type;

  Future<SshSession> createForConnection(String connectionId) {
    return _getOrCreateSharedSession(connectionId);
  }

  Future<SshSession> resolveFromRequest(Request request) async {
    final sessionId = request.url.queryParameters['sessionId'];
    if (sessionId != null) {
      final session = _sshService.getSession(sessionId);
      if (session != null) {
        return session;
      }

      throw StateError('Session not found');
    }

    final connectionId = request.url.queryParameters['connectionId'];
    if (connectionId == null || connectionId.isEmpty) {
      throw ArgumentError('Missing connectionId or sessionId');
    }

    return _getOrCreateSharedSession(connectionId);
  }

  Future<void> closeFromRequest(Request request) async {
    final sessionId = request.url.queryParameters['sessionId'];
    final connectionId = request.url.queryParameters['connectionId'];

    String? targetSessionId = sessionId;
    if (targetSessionId == null && connectionId != null) {
      targetSessionId = _sharedSessionIds.remove(connectionId);
    }

    if (targetSessionId == null) {
      throw ArgumentError('Missing connectionId or sessionId');
    }

    _removeSharedSessionById(targetSessionId);
    await _sshService.closeSession(targetSessionId);
  }

  Response errorResponse(Object error) {
    if (error is ArgumentError) {
      return Result.fail(400, error.message?.toString() ?? error.toString());
    }

    if (error is StateError) {
      return Result.fail(404, error.message);
    }

    return Result.fail(500, error.toString());
  }

  Future<SshSession> _getOrCreateSharedSession(String connectionId) async {
    final existingSessionId = _sharedSessionIds[connectionId];
    if (existingSessionId != null) {
      final existingSession = _sshService.getSession(existingSessionId);
      if (existingSession != null) {
        return existingSession;
      }

      _sharedSessionIds.remove(connectionId);
    }

    final pendingSession = _pendingSharedSessions[connectionId];
    if (pendingSession != null) {
      return pendingSession;
    }

    final nextSession = _createSession(connectionId)
        .then((session) {
          _sharedSessionIds[connectionId] = session.id;
          return session;
        })
        .whenComplete(() {
          _pendingSharedSessions.remove(connectionId);
        });

    _pendingSharedSessions[connectionId] = nextSession;
    return nextSession;
  }

  Future<SshSession> _createSession(String connectionId) {
    return switch (_type) {
      SharedSshSessionType.shell => _sshService.createShell(connectionId),
      SharedSshSessionType.sftp => _sshService.createSftpSession(connectionId),
    };
  }

  void _removeSharedSessionById(String sessionId) {
    _sharedSessionIds.removeWhere((_, value) => value == sessionId);
  }
}
