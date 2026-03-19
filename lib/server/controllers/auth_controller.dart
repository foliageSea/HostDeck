import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:logging/logging.dart';
import '../services/ssh_service.dart';
import '../models/result.dart';

class AuthController {
  final _log = Logger('AuthController');
  final SshService _sshService;

  AuthController(this._sshService);

  Future<Response> connect(Request request) async {
    try {
      final payload = await request.readAsString();
      final data = jsonDecode(payload);
      
      final session = await _sshService.connect(
        host: data['host'],
        port: int.parse(data['port'].toString()),
        username: data['username'],
        password: data['password'],
        privateKey: data['privateKey'],
      );
      
      return Result.ok({
        'sessionId': session.id,
        'connectionId': session.connectionId,
      });
    } catch (e) {
      _log.severe('Connect Error: $e');
      return Result.fail(500, e.toString());
    }
  }
}
