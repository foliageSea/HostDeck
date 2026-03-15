import 'dart:convert';
import 'package:shelf/shelf.dart';
import '../services/ssh_service.dart';
import '../services/monitor_service.dart';
import '../models/result.dart';

class SystemController {
  final SshService _sshService;
  final MonitorService _monitorService;

  SystemController(this._sshService, this._monitorService);

  Response status(Request request) {
    return Result.ok({'status': 'running'});
  }

  Future<Response> monitor(Request request) async {
    final sessionId = request.url.queryParameters['sessionId'];
    if (sessionId == null) {
      return Result.fail(400, 'Missing sessionId parameter');
    }

    final session = _sshService.getSession(sessionId);
    if (session == null) {
      return Result.fail(404, 'Session not found');
    }

    try {
      final status = await _monitorService.getSystemStatus(session);
      return Result.ok(status);
    } catch (e) {
      return Result.fail(500, e.toString());
    }
  }
}
