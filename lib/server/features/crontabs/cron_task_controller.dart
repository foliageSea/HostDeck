import 'dart:convert';

import 'package:shelf/shelf.dart';

import 'package:host_deck/server/core/http/result.dart';
import 'package:host_deck/server/core/ssh/shared_ssh_session_resolver.dart';
import 'package:host_deck/server/core/ssh/ssh_service.dart';
import 'package:host_deck/server/core/ssh/ssh_session.dart';
import 'package:host_deck/server/features/crontabs/cron_task.dart';
import 'package:host_deck/server/features/crontabs/cron_task_repository.dart';
import 'package:host_deck/server/features/crontabs/cron_task_service.dart';

class CronTaskController {
  final SshService _sshService;
  final CronTaskRepository _repository;
  final CronTaskService _service;
  final SharedSshSessionResolver _sessionResolver;

  CronTaskController(this._sshService, this._repository, this._service)
    : _sessionResolver = SharedSshSessionResolver(
        _sshService,
        type: SharedSshSessionType.sftp,
        purpose: SshSessionPurpose.cronTask,
      );

  Future<Response> list(Request request) async {
    final serverId = _serverId(request);
    if (serverId == null) return Result.fail(400, 'Missing serverId');
    final validation = _validateConnection(request, serverId);
    if (validation != null) return validation;
    return Result.ok(
      _service.list(serverId).map((task) => task.toJson()).toList(),
    );
  }

  Future<Response> create(Request request) async {
    try {
      final task = CronTask.fromJson(await _readJson(request));
      return _withSession(request, task.serverId!, (session) async {
        final created = await _service.create(session, task);
        return Result.ok(created.toJson());
      });
    } on ArgumentError catch (e) {
      return Result.fail(400, e.message?.toString() ?? '无效的定时任务。');
    } catch (e) {
      return Result.fail(500, e.toString());
    }
  }

  Future<Response> update(Request request, String idString) async {
    final id = int.tryParse(idString);
    if (id == null) return Result.fail(400, 'Invalid task ID');
    try {
      final task = CronTask.fromJson(await _readJson(request));
      return _withSession(request, task.serverId!, (session) async {
        final updated = await _service.update(session, id, task);
        return updated == null
            ? Result.fail(404, '定时任务不存在。')
            : Result.ok(updated.toJson());
      });
    } on ArgumentError catch (e) {
      return Result.fail(400, e.message?.toString() ?? '无效的定时任务。');
    } catch (e) {
      return Result.fail(500, e.toString());
    }
  }

  Future<Response> delete(Request request, String idString) async {
    final id = int.tryParse(idString);
    final serverId = _serverId(request);
    if (id == null) return Result.fail(400, 'Invalid task ID');
    if (serverId == null) return Result.fail(400, 'Missing serverId');
    return _withSession(request, serverId, (session) async {
      final deleted = await _service.delete(session, id, serverId);
      return deleted
          ? Result.ok({'success': true})
          : Result.fail(404, '定时任务不存在。');
    });
  }

  Future<Response> runNow(Request request, String idString) async {
    final id = int.tryParse(idString);
    final serverId = _serverId(request);
    if (id == null) return Result.fail(400, 'Invalid task ID');
    if (serverId == null) return Result.fail(400, 'Missing serverId');
    final task = _repository.get(id);
    if (task == null || task.serverId != serverId) {
      return Result.fail(404, '定时任务不存在。');
    }
    return _withSession(request, serverId, (session) async {
      return Result.ok((await _service.runNow(session, task)).toJson());
    });
  }

  Future<Response> listHistory(Request request, String idString) async {
    final id = int.tryParse(idString);
    final serverId = _serverId(request);
    if (id == null) return Result.fail(400, 'Invalid task ID');
    if (serverId == null) return Result.fail(400, 'Missing serverId');
    final task = _repository.get(id);
    if (task == null || task.serverId != serverId) {
      return Result.fail(404, '定时任务不存在。');
    }
    final limit =
        int.tryParse(request.url.queryParameters['limit'] ?? '') ?? 100;
    final offset =
        int.tryParse(request.url.queryParameters['offset'] ?? '') ?? 0;
    return Result.ok(
      _service
          .listHistory(id, limit: limit, offset: offset)
          .map((item) => item.toJson())
          .toList(),
    );
  }

  Future<Response> syncHistory(Request request, String idString) async {
    final id = int.tryParse(idString);
    final serverId = _serverId(request);
    if (id == null) return Result.fail(400, 'Invalid task ID');
    if (serverId == null) return Result.fail(400, 'Missing serverId');
    final task = _repository.get(id);
    if (task == null || task.serverId != serverId) {
      return Result.fail(404, '定时任务不存在。');
    }
    return _withSession(request, serverId, (session) async {
      final imported = await _service.syncHistory(session, task);
      return Result.ok({'imported': imported});
    });
  }

  Future<Response> _withSession(
    Request request,
    int serverId,
    Future<Response> Function(SshSession session) action,
  ) async {
    final validation = _validateConnection(request, serverId);
    if (validation != null) return validation;
    final connectionId = _connectionId(request)!;
    try {
      return await action(
        await _sessionResolver.createForConnection(connectionId),
      );
    } catch (e) {
      return Result.fail(500, e.toString());
    }
  }

  String? _connectionId(Request request) {
    final value = request.url.queryParameters['connectionId']?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  int? _serverId(Request request) {
    final value = request.url.queryParameters['serverId']?.trim();
    return value == null || value.isEmpty ? null : int.tryParse(value);
  }

  Response? _validateConnection(Request request, int serverId) {
    final connectionId = _connectionId(request);
    if (connectionId == null) return Result.fail(400, 'Missing connectionId');
    if (_sshService.getClient(connectionId) == null) {
      return Result.fail(404, 'Connection not found');
    }
    if (_sshService.getServerId(connectionId) != serverId) {
      return Result.fail(403, 'Connection does not belong to server');
    }
    return null;
  }

  Future<Map<String, dynamic>> _readJson(Request request) async {
    final payload = await request.readAsString();
    if (payload.trim().isEmpty) throw ArgumentError('请求内容不能为空。');
    final decoded = jsonDecode(payload);
    if (decoded is! Map<String, dynamic>) throw ArgumentError('无效的请求内容。');
    return decoded;
  }
}
