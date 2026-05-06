import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:shelf/shelf.dart';

import '../services/ssh_service.dart';
import '../models/result.dart';
import '../services/monitor_history_service.dart';

class AuthController {
  final _log = Logger('AuthController');
  final MonitorHistoryService _monitorHistoryService;
  final SshService _sshService;

  AuthController(this._sshService, this._monitorHistoryService);

  Future<Response> connect(Request request) async {
    try {
      final payload = await request.readAsString();
      final data = jsonDecode(payload);

      final connectionId = await _sshService.connect(
        host: data['host'],
        port: int.parse(data['port'].toString()),
        username: data['username'],
        password: data['password'],
        privateKey: data['privateKey'],
      );

      return Result.ok({'connectionId': connectionId});
    } catch (e) {
      _log.severe('Connect Error: $e');
      return Result.fail(500, e.toString());
    }
  }

  Future<Response> disconnect(Request request) async {
    try {
      final connectionId = request.url.queryParameters['connectionId'];
      if (connectionId == null || connectionId.isEmpty) {
        return Result.fail(400, 'Missing connectionId');
      }

      await _sshService.disconnect(connectionId);
      _monitorHistoryService.clearConnection(connectionId);
      return Result.ok({'success': true});
    } catch (e) {
      _log.severe('Disconnect Error: $e');
      return Result.fail(500, e.toString());
    }
  }
}
