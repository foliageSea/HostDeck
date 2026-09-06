import 'dart:convert';

import 'package:shelf/shelf.dart';

import 'package:host_deck/server/core/http/result.dart';
import 'package:host_deck/server/features/port_forwards/chrome_launcher.dart';
import 'package:host_deck/server/features/port_forwards/secure_browser_tunnel_service.dart';

class SecureBrowserTunnelController {
  final SecureBrowserTunnelService _service;
  final ChromeLauncher? _chromeLauncher;

  const SecureBrowserTunnelController(
    this._service, {
    ChromeLauncher? chromeLauncher,
  }) : _chromeLauncher = chromeLauncher;

  Response list(Request request) {
    return Result.ok(_service.list().map((tunnel) => tunnel.toJson()).toList());
  }

  Response capabilities(Request request) {
    final launcher = _chromeLauncher;
    return Result.ok({
      'launchEnabled': launcher != null,
      'chromeDetected': launcher?.isChromeDetected ?? false,
    });
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

  Future<Response> launch(Request request, String id) async {
    final launcher = _chromeLauncher;
    if (launcher == null) {
      return Result.fail(403, '服务端安全浏览器启动功能未启用。');
    }
    final tunnel = _service.getById(id);
    if (tunnel == null) {
      return Result.fail(404, '安全浏览器代理不存在或已停止。');
    }

    try {
      final payload = await request.readAsString();
      String? url;
      if (payload.trim().isNotEmpty) {
        final decoded = jsonDecode(payload);
        if (decoded is! Map<String, dynamic>) {
          throw const FormatException('请求内容必须是 JSON 对象。');
        }
        final value = decoded['url'];
        if (value != null && value is! String) {
          throw const FormatException('url 必须是字符串。');
        }
        url = value as String?;
      }
      final result = await launcher.launch(
        profileId: tunnel.id,
        proxyPort: tunnel.bindPort,
        url: url,
      );
      if (!result.success) {
        final status = result.reason == 'invalid-request' ? 400 : 409;
        return Result.fail(status, result.message ?? 'Google Chrome 启动失败。');
      }
      return Result.ok(result.toJson());
    } on FormatException catch (error) {
      return Result.fail(400, error.message);
    } catch (error) {
      return Result.fail(500, error.toString());
    }
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
