import 'dart:convert';
import 'package:shelf/shelf.dart';
import '../services/ssh_service.dart';

class AuthController {
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
      
      return Response.ok(jsonEncode({'sessionId': session.id}), 
        headers: {'content-type': 'application/json'});
    } catch (e) {
      print('Connect Error: $e');
      return Response.internalServerError(body: jsonEncode({'error': e.toString()}),
        headers: {'content-type': 'application/json'});
    }
  }
}
