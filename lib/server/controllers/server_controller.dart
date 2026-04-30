import 'dart:convert';
import 'package:shelf/shelf.dart';
import '../models/result.dart';
import '../models/server_config.dart';
import '../repositories/server_repository.dart';

class ServerController {
  final ServerRepository _serverRepository;

  ServerController(this._serverRepository);

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
      return Result.ok(newServer.toJson());
    } catch (e) {
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
      final server = ServerConfig.fromJson(data);

      final success = _serverRepository.updateServer(id, server);
      if (success) {
        return Result.ok({'success': true});
      } else {
        return Result.fail(404, 'Server not found');
      }
    } catch (e) {
      return Result.fail(500, e.toString());
    }
  }

  Future<Response> delete(Request request, String idStr) async {
    try {
      final id = int.tryParse(idStr);
      if (id == null) {
        return Result.fail(400, 'Invalid ID');
      }

      final success = _serverRepository.deleteServer(id);
      if (success) {
        return Result.ok({'success': true});
      } else {
        return Result.fail(404, 'Server not found');
      }
    } catch (e) {
      return Result.fail(500, e.toString());
    }
  }
}
