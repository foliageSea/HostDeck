import 'dart:convert';

import 'package:shelf/shelf.dart';

import 'package:host_deck/server/core/http/result.dart';
import 'package:host_deck/server/features/port_forwards/secure_browser_tunnel_service.dart';

class SecureBrowserTunnelController {
  final SecureBrowserTunnelService _service;

  const SecureBrowserTunnelController(this._service);

  Response list(Request request) {
    return Result.ok(_service.list().map((tunnel) => tunnel.toJson()).toList());
  }

  Future<Response> create(Request request) async {
    try {
      final data = await _readJson(request);
      final connectionId = _requiredString(data, 'connectionId');
      final tunnel = await _service.create(connectionId: connectionId);
      return Result.ok(tunnel.toJson());
    } on FormatException catch (error) {
      return Result.fail(400, error.message);
    } on ArgumentError catch (error) {
      return Result.fail(400, error.message?.toString() ?? error.toString());
    } on StateError catch (error) {
      return Result.fail(409, error.message);
    } catch (error) {
      return Result.fail(500, error.toString());
    }
  }

  Future<Response> stop(Request request, String id) async {
    await _service.stop(id);
    return Result.ok({'success': true});
  }

  Future<Map<String, dynamic>> _readJson(Request request) async {
    final payload = await request.readAsString();
    if (payload.trim().isEmpty) {
      throw const FormatException('请求内容不能为空。');
    }
    final decoded = jsonDecode(payload);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('请求内容必须是 JSON 对象。');
    }
    return decoded;
  }

  String _requiredString(Map<String, dynamic> data, String key) {
    final value = data[key]?.toString().trim();
    if (value == null || value.isEmpty) {
      throw FormatException('缺少 $key。');
    }
    return value;
  }
}
