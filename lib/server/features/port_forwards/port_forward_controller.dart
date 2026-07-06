import 'dart:convert';

import 'package:shelf/shelf.dart';

import 'package:host_deck/server/core/http/result.dart';
import 'package:host_deck/server/features/port_forwards/port_forward_repository.dart';
import 'package:host_deck/server/features/port_forwards/port_forward_rule.dart';
import 'package:host_deck/server/features/port_forwards/port_forward_service.dart';

class PortForwardController {
  final PortForwardRepository _repository;
  final PortForwardService _service;

  PortForwardController(this._repository, this._service);

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
      return Result.ok(_ruleWithStatus(rule));
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
      return Result.ok(_ruleWithStatus(nextRule));
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

      await _service.stop(id);
      final success = _repository.deleteRule(id);
      if (!success) {
        return Result.fail(404, 'Port forward rule not found');
      }

      return Result.ok({'success': true});
    } catch (e) {
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
      return Result.ok(_ruleWithStatus(_repository.getRule(id) ?? rule));
    } catch (e) {
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
      return Result.ok(
        rule == null ? {'success': true} : _ruleWithStatus(rule),
      );
    } catch (e) {
      return Result.fail(500, e.toString());
    }
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
