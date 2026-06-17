import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:shelf/shelf.dart';

import '../services/ssh_service.dart';
import '../models/server_config.dart';
import '../models/result.dart';
import '../repositories/server_repository.dart';
import '../services/monitor_history_service.dart';

class AuthController {
  final _log = Logger('AuthController');
  final MonitorHistoryService _monitorHistoryService;
  final ServerRepository _serverRepository;
  final SshService _sshService;

  AuthController(
    this._sshService,
    this._monitorHistoryService,
    this._serverRepository,
  );

  Future<Response> connect(Request request) async {
    try {
      final payload = await request.readAsString();
      final data = jsonDecode(payload);
      final server = _getSavedServer(data['serverId']);
      _logAuthRequest('Connect', data['serverId'], server);

      final connectionId = await _sshService.connect(
        host: server?.host ?? data['host'],
        port: server?.port ?? int.parse(data['port'].toString()),
        username: server?.username ?? data['username'],
        password: server?.password ?? _stringOrNull(data['password']),
        privateKey: server?.privateKey ?? _stringOrNull(data['privateKey']),
      );

      return Result.ok({'connectionId': connectionId});
    } catch (e) {
      _log.severe('Connect Error: $e');
      return Result.fail(500, e.toString());
    }
  }

  Future<Response> testConnect(Request request) async {
    try {
      final payload = await request.readAsString();
      final data = jsonDecode(payload);
      final server = _getSavedServer(data['serverId']);
      _logAuthRequest('Test connect', data['serverId'], server);

      final connectionId = await _sshService.connect(
        host: server?.host ?? data['host'],
        port: server?.port ?? int.parse(data['port'].toString()),
        username: server?.username ?? data['username'],
        password: server?.password ?? _stringOrNull(data['password']),
        privateKey: server?.privateKey ?? _stringOrNull(data['privateKey']),
      );

      await _sshService.disconnect(connectionId);
      return Result.ok({'success': true});
    } catch (e) {
      _log.severe('Test Connect Error: $e');
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

  ServerConfig? _getSavedServer(dynamic serverId) {
    if (serverId == null) return null;

    final id = serverId is int ? serverId : int.tryParse(serverId.toString());
    if (id == null) {
      throw FormatException('Invalid serverId: $serverId');
    }

    final server = _serverRepository.getServer(id);
    if (server == null) {
      throw StateError('Server not found');
    }

    return server;
  }

  void _logAuthRequest(String action, dynamic serverId, ServerConfig? server) {
    if (serverId == null) {
      _log.info('$action request uses inline credentials');
      return;
    }

    _log.info(
      '$action request uses saved server id=$serverId '
      'hasPassword=${server?.password?.isNotEmpty == true} '
      'hasPrivateKey=${server?.privateKey?.isNotEmpty == true}',
    );
  }

  String? _stringOrNull(dynamic value) {
    if (value is! String || value.isEmpty) return null;
    return value;
  }
}
