import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:logging/logging.dart';

import '../models/result.dart';
import '../services/client_session_service.dart';
import '../services/ssh_service.dart';

class AuthController {
  final _log = Logger('AuthController');
  final ClientSessionService _clientSessionService;
  final SshService _sshService;

  AuthController(this._sshService, this._clientSessionService);

  Future<Response> connect(Request request) async {
    final clientSession = _clientSessionService.resolve(request);

    try {
      final payload = await request.readAsString();
      final data = jsonDecode(payload);

      final connection = await _sshService.connect(
        clientId: clientSession.clientId,
        host: data['host'],
        port: int.parse(data['port'].toString()),
        username: data['username'],
        password: data['password'],
        privateKey: data['privateKey'],
      );

      return _withSessionHeaders(
        Result.ok(connection.toClientJson()),
        clientSession,
      );
    } catch (e) {
      _log.severe('Connect Error: $e');
      return _withSessionHeaders(
        Result.fail(500, e.toString()),
        clientSession,
      );
    }
  }

  Future<Response> status(Request request) async {
    final clientSession = _clientSessionService.resolve(request);

    try {
      final connection = _sshService.getConnectionForClient(clientSession.clientId);

      return _withSessionHeaders(
        Result.ok(connection?.toClientJson()),
        clientSession,
      );
    } catch (e) {
      _log.severe('Status Error: $e');
      return _withSessionHeaders(
        Result.fail(500, e.toString()),
        clientSession,
      );
    }
  }

  Future<Response> disconnect(Request request) async {
    final clientSession = _clientSessionService.resolve(request);

    try {
      final connectionId = request.url.queryParameters['connectionId'];
      if (connectionId != null && connectionId.isNotEmpty) {
        await _sshService.disconnect(connectionId);
      } else {
        await _sshService.disconnectClient(clientSession.clientId);
      }

      return _withSessionHeaders(
        Result.ok({'success': true}),
        clientSession,
      );
    } catch (e) {
      _log.severe('Disconnect Error: $e');
      return _withSessionHeaders(
        Result.fail(500, e.toString()),
        clientSession,
      );
    }
  }

  Response _withSessionHeaders(Response response, ClientSession session) {
    return response.change(
      headers: {
        ...response.headers,
        ..._clientSessionService.buildSessionHeaders(session),
      },
    );
  }
}
