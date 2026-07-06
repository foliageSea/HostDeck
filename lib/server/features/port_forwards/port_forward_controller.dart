import 'dart:convert';

import 'package:shelf/shelf.dart';

import 'package:host_deck/server/core/http/result.dart';
import 'package:host_deck/server/features/operation_logs/operation_log_service.dart';
import 'package:host_deck/server/features/port_forwards/port_forward_repository.dart';
import 'package:host_deck/server/features/port_forwards/port_forward_rule.dart';
import 'package:host_deck/server/features/port_forwards/port_forward_service.dart';

class PortForwardController {
  final PortForwardRepository _repository;
  final OperationLogService _operationLogService;
  final PortForwardService _service;

  PortForwardController(
    this._repository,
    this._service,
    this._operationLogService,
  );

  Future<Response> list(Request request) async {
    try {
      final rules = _repository.getAllRules();
      return Result.ok(rules.map(_ruleWithStatus).toList());
    } catch (e) {
      return Result.fail(500, e.toString());
    }
  }

  Future<Response> create(Request request) async {
    try {
      final data = await _readJson(request);
      final inputRule = PortForwardRule.fromJson(data);
      var rule = _repository.addRule(inputRule.copyWith(enabled: false));
      if (inputRule.enabled) {
        await _service.start(_requireConnectionId(data), rule);
        rule = _repository.getRule(rule.id!) ?? rule;
      }
      _operationLogService.success(
        category: 'portForward',
        action: 'create',
        target: _ruleTarget(rule),
        connectionId: data['connectionId']?.toString(),
      );
      return Result.ok(_ruleWithStatus(rule));
    } catch (e) {
      _operationLogService.failure(
        category: 'portForward',
        action: 'create',
        target: '端口转发规则',
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

      final data = await _readJson(request);
      final inputRule = PortForwardRule.fromJson(data).copyWith(id: id);
      final rule = inputRule.copyWith(enabled: false);
      final success = _repository.updateRule(id, rule);
      if (!success) {
        return Result.fail(404, 'Port forward rule not found');
      }

      await _service.stop(id);
      if (inputRule.enabled) {
        await _service.start(_requireConnectionId(data), rule);
      }

      final nextRule = _repository.getRule(id) ?? inputRule;
      _operationLogService.success(
        category: 'portForward',
        action: 'update',
        target: _ruleTarget(nextRule),
        connectionId: data['connectionId']?.toString(),
      );
      return Result.ok(_ruleWithStatus(nextRule));
    } catch (e) {
      _operationLogService.failure(
        category: 'portForward',
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

      await _service.stop(id);
      final rule = _repository.getRule(id);
      final success = _repository.deleteRule(id);
      if (!success) {
        return Result.fail(404, 'Port forward rule not found');
      }

      _operationLogService.success(
        category: 'portForward',
        action: 'delete',
        target: rule == null ? id.toString() : _ruleTarget(rule),
      );
      return Result.ok({'success': true});
    } catch (e) {
      _operationLogService.failure(
        category: 'portForward',
        action: 'delete',
        target: idStr,
        error: e,
      );
      return Result.fail(500, e.toString());
    }
  }

  Future<Response> start(Request request, String idStr) async {
    try {
      final id = int.tryParse(idStr);
      if (id == null) {
        return Result.fail(400, 'Invalid ID');
      }

      final rule = _repository.getRule(id);
      if (rule == null) {
        return Result.fail(404, 'Port forward rule not found');
      }

      final data = await _readJson(request);
      await _service.start(_requireConnectionId(data), rule);
      _operationLogService.success(
        category: 'portForward',
        action: 'start',
        target: _ruleTarget(rule),
        connectionId: data['connectionId']?.toString(),
      );
      return Result.ok(_ruleWithStatus(_repository.getRule(id) ?? rule));
    } catch (e) {
      _operationLogService.failure(
        category: 'portForward',
        action: 'start',
        target: idStr,
        error: e,
      );
      return Result.fail(500, e.toString());
    }
  }

  Future<Response> stop(Request request, String idStr) async {
    try {
      final id = int.tryParse(idStr);
      if (id == null) {
        return Result.fail(400, 'Invalid ID');
      }

      await _service.stop(id);
      final rule = _repository.getRule(id);
      _operationLogService.success(
        category: 'portForward',
        action: 'stop',
        target: rule == null ? id.toString() : _ruleTarget(rule),
      );
      return Result.ok(
        rule == null ? {'success': true} : _ruleWithStatus(rule),
      );
    } catch (e) {
      _operationLogService.failure(
        category: 'portForward',
        action: 'stop',
        target: idStr,
        error: e,
      );
      return Result.fail(500, e.toString());
    }
  }

  String _ruleTarget(PortForwardRule rule) {
    return '${rule.bindHost}:${rule.localPort} -> ${rule.remoteHost}:${rule.remotePort}';
  }

  Future<Map<String, dynamic>> _readJson(Request request) async {
    final payload = await request.readAsString();
    if (payload.trim().isEmpty) {
      return {};
    }
    return jsonDecode(payload) as Map<String, dynamic>;
  }

  String _requireConnectionId(Map<String, dynamic> data) {
    final connectionId = data['connectionId']?.toString().trim();
    if (connectionId == null || connectionId.isEmpty) {
      throw ArgumentError('Missing connectionId');
    }
    return connectionId;
  }

  Map<String, dynamic> _ruleWithStatus(PortForwardRule rule) {
    final status = _service.statusFor(rule.id ?? -1);
    return {
      ...rule.toJson(),
      ...status,
      'enabled': status['status'] == 'running',
    };
  }
}
