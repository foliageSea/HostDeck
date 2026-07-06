import 'dart:convert';
import 'package:shelf/shelf.dart';

import 'package:host_deck/server/core/http/result.dart';
import 'package:host_deck/server/features/operation_logs/operation_log_service.dart';
import 'package:host_deck/server/features/servers/server_config.dart';
import 'package:host_deck/server/features/servers/server_repository.dart';

class ServerController {
  final ServerRepository _serverRepository;
  final OperationLogService _operationLogService;

  ServerController(this._serverRepository, this._operationLogService);

  Future<Response> list(Request request) async {
    try {
      final servers = _serverRepository.getAllServers();
      return Result.ok(servers.map((s) => s.toJson()).toList());
    } catch (e) {
      return Result.fail(500, e.toString());
    }
  }

  Future<Response> create(Request request) async {
    try {
      final payload = await request.readAsString();
      final data = jsonDecode(payload);
      final server = ServerConfig.fromJson(data);
      final newServer = _serverRepository.addServer(server);
      _operationLogService.success(
        category: 'server',
        action: 'create',
        target: _serverTarget(newServer),
        detail: {'serverId': newServer.id},
      );
      return Result.ok(newServer.toJson());
    } catch (e) {
      _operationLogService.failure(
        category: 'server',
        action: 'create',
        target: '保存主机',
        error: e,
      );
      return Result.fail(500, e.toString());
    }
  }

  Future<Response> update(Request request, String idStr) async {
    try {
      final id = int.tryParse(idStr);
      if (id == null) {
        return Result.fail(400, 'Invalid ID');
      }

      final payload = await request.readAsString();
      final data = jsonDecode(payload);
      final existing = _serverRepository.getServer(id);
      if (existing == null) {
        return Result.fail(404, 'Server not found');
      }

      final server = ServerConfig(
        id: id,
        name: data['name'] as String? ?? existing.name,
        host: data['host'] as String? ?? existing.host,
        port: data['port'] is int
            ? data['port']
            : int.tryParse(data['port']?.toString() ?? '') ?? existing.port,
        username: data['username'] as String? ?? existing.username,
        password: data.containsKey('password')
            ? data['password'] as String?
            : existing.password,
        privateKey: data.containsKey('privateKey')
            ? data['privateKey'] as String?
            : existing.privateKey,
        createdAt: existing.createdAt,
      );

      final success = _serverRepository.updateServer(id, server);
      if (success) {
        _operationLogService.success(
          category: 'server',
          action: 'update',
          target: _serverTarget(server),
          detail: {'serverId': id},
        );
        return Result.ok({'success': true});
      } else {
        return Result.fail(404, 'Server not found');
      }
    } catch (e) {
      _operationLogService.failure(
        category: 'server',
        action: 'update',
        target: idStr,
        error: e,
      );
      return Result.fail(500, e.toString());
    }
  }

  Future<Response> delete(Request request, String idStr) async {
    try {
      final id = int.tryParse(idStr);
      if (id == null) {
        return Result.fail(400, 'Invalid ID');
      }

      final existing = _serverRepository.getServer(id);
      final success = _serverRepository.deleteServer(id);
      if (success) {
        _operationLogService.success(
          category: 'server',
          action: 'delete',
          target: existing == null ? id.toString() : _serverTarget(existing),
          detail: {'serverId': id},
        );
        return Result.ok({'success': true});
      } else {
        return Result.fail(404, 'Server not found');
      }
    } catch (e) {
      _operationLogService.failure(
        category: 'server',
        action: 'delete',
        target: idStr,
        error: e,
      );
      return Result.fail(500, e.toString());
    }
  }

  String _serverTarget(ServerConfig server) {
    return '${server.username}@${server.host}:${server.port}';
  }
}
