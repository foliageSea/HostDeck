import 'dart:convert';
import 'package:shelf/shelf.dart';
import '../services/ssh_service.dart';
import '../services/monitor_service.dart';

class SystemController {
  final SshService _sshService;
  final MonitorService _monitorService;

  SystemController(this._sshService, this._monitorService);

  Response status(Request request) {
    return Response.ok(
      '{"status": "running"}',
      headers: {'content-type': 'application/json'},
    );
  }

  Future<Response> monitor(Request request) async {
    final sessionId = request.url.queryParameters['sessionId'];
    if (sessionId == null) {
      return _errorResponse(
        400,
        'MISSING_SESSION_ID',
        'Missing sessionId parameter',
      );
    }

    final session = _sshService.getSession(sessionId);
    if (session == null) {
      return _errorResponse(
        404,
        'SESSION_NOT_FOUND',
        'Session not found or expired',
      );
    }

    try {
      final status = await _monitorService.getSystemStatus(session);
      return Response.ok(
        jsonEncode(status),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      return _errorResponse(500, 'MONITOR_ERROR', e.toString());
    }
  }

  Response _errorResponse(int statusCode, String code, String message) {
    return Response(
      statusCode,
      body: jsonEncode({'code': code, 'message': message}),
      headers: {'content-type': 'application/json'},
    );
  }
}
