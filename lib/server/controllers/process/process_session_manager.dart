import '../../models/ssh_session.dart';
import '../../services/ssh_service.dart';

class ProcessSessionManager {
  final SshService _sshService;
  final Map<String, String> _sharedSessionIds = {};
  final Map<String, Future<SshSession>> _pendingSharedSessions = {};

  ProcessSessionManager(this._sshService);

  Future<SshSession> resolveSession(String? connectionId) async {
    if (connectionId == null || connectionId.isEmpty) {
      throw ArgumentError('Missing connectionId');
    }

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

    if (_sshService.getClient(connectionId) == null) {
      throw StateError('Connection not found');
    }

    final nextSession = _sshService
        .createSftpSession(connectionId)
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
}
