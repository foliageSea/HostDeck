import 'package:shelf/shelf.dart';

import '../models/result.dart';
import '../models/ssh_session.dart';
import '../services/process_service.dart';
import '../services/ssh_service.dart';

class ProcessController {
  final SshService _sshService;
  final ProcessService _processService;
  final Map<String, String> _sharedSessionIds = {};

  ProcessController(this._sshService, this._processService);

  Future<Response> list(Request request) async {
    return _withSession(request, (session) async {
      try {
        final processes = await _processService.listProcesses(session);
        return Result.ok(processes.map((process) => process.toJson()).toList());
      } catch (e) {
        return Result.fail(500, e.toString());
      }
    });
  }

  Future<Response> kill(Request request, String pid) async {
    final processId = int.tryParse(pid);
    if (processId == null || processId <= 0) {
      return Result.fail(400, 'Invalid pid');
    }

    return _withSession(request, (session) async {
      try {
        await _processService.killProcess(session, processId);
        return Result.ok({'success': true});
      } catch (e) {
        return Result.fail(500, e.toString());
      }
    });
  }

  Future<Response> _withSession(
    Request request,
    Future<Response> Function(SshSession session) action,
  ) async {
    final connectionId = request.url.queryParameters['connectionId'];
    if (connectionId == null || connectionId.isEmpty) {
      return Result.fail(400, 'Missing connectionId');
    }

    if (_sshService.getClient(connectionId) == null) {
      return Result.fail(404, 'Connection not found');
    }

    try {
      final session = await _getOrCreateSession(connectionId);
      return action(session);
    } catch (e) {
      return Result.fail(500, e.toString());
    }
  }

  Future<SshSession> _getOrCreateSession(String connectionId) async {
    final existingSessionId = _sharedSessionIds[connectionId];
    if (existingSessionId != null) {
      final existingSession = _sshService.getSession(existingSessionId);
      if (existingSession != null) {
        return existingSession;
      }

      _sharedSessionIds.remove(connectionId);
    }

    final session = await _sshService.createSftpSession(connectionId);
    _sharedSessionIds[connectionId] = session.id;
    return session;
  }
}
