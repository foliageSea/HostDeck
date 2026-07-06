import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:shelf/shelf.dart';

import 'package:host_deck/server/core/http/result.dart';
import 'package:host_deck/server/core/ssh/ssh_service.dart';
import 'package:host_deck/server/features/operation_logs/operation_log_service.dart';
import 'package:host_deck/server/features/servers/server_config.dart';
import 'package:host_deck/server/features/servers/server_repository.dart';
import 'package:host_deck/server/features/system/monitor_history_service.dart';

class AuthController {
  final _log = Logger('AuthController');
  final MonitorHistoryService _monitorHistoryService;
  final OperationLogService _operationLogService;
  final ServerRepository _serverRepository;
  final SshService _sshService;

  AuthController(
    this._sshService,
    this._monitorHistoryService,
    this._serverRepository,
    this._operationLogService,
  );

  Future<Response> connect(Request request) async {
    try {
      final payload = await request.readAsString();
      final data = jsonDecode(payload);
      final server = _getSavedServer(data['serverId']);
      _logAuthRequest('Connect', data['serverId'], server);
      final target = _connectionTarget(data, server);

      final connectionId = await _sshService.connect(
        host: server?.host ?? data['host'],
        port: server?.port ?? int.parse(data['port'].toString()),
        username: server?.username ?? data['username'],
        password: server?.password ?? _stringOrNull(data['password']),
        privateKey: server?.privateKey ?? _stringOrNull(data['privateKey']),
      );

      _operationLogService.success(
        category: 'auth',
        action: 'connect',
        target: target,
        connectionId: connectionId,
      );
      return Result.ok({'connectionId': connectionId});
    } catch (e) {
      _log.severe('Connect Error: $e');
      _operationLogService.failure(
        category: 'auth',
        action: 'connect',
        target: 'SSH 连接',
        error: e,
      );
      return Result.fail(500, e.toString());
    }
  }

  Future<Response> testConnect(Request request) async {
    try {
      final payload = await request.readAsString();
      final data = jsonDecode(payload);
      final server = _getSavedServer(data['serverId']);
      _logAuthRequest('Test connect', data['serverId'], server);
      final target = _connectionTarget(data, server);

      final connectionId = await _sshService.connect(
        host: server?.host ?? data['host'],
        port: server?.port ?? int.parse(data['port'].toString()),
        username: server?.username ?? data['username'],
        password: server?.password ?? _stringOrNull(data['password']),
        privateKey: server?.privateKey ?? _stringOrNull(data['privateKey']),
      );

      await _sshService.disconnect(connectionId);
      _operationLogService.success(
        category: 'auth',
        action: 'testConnect',
        target: target,
      );
      return Result.ok({'success': true});
    } catch (e) {
      _log.severe('Test Connect Error: $e');
      _operationLogService.failure(
        category: 'auth',
        action: 'testConnect',
        target: 'SSH 连接测试',
        error: e,
      );
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
      _operationLogService.success(
        category: 'auth',
        action: 'disconnect',
        target: connectionId,
        connectionId: connectionId,
      );
      return Result.ok({'success': true});
    } catch (e) {
      _log.severe('Disconnect Error: $e');
      _operationLogService.failure(
        category: 'auth',
        action: 'disconnect',
        target: request.url.queryParameters['connectionId'],
        connectionId: request.url.queryParameters['connectionId'],
        error: e,
      );
      return Result.fail(500, e.toString());
    }
  }

  String _connectionTarget(Map<String, dynamic> data, ServerConfig? server) {
    final username = server?.username ?? data['username']?.toString() ?? '';
    final host = server?.host ?? data['host']?.toString() ?? '';
    final port = server?.port ?? data['port']?.toString() ?? '';
    return '$username@$host:$port';
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
