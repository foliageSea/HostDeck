import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:shelf/shelf.dart';

import 'package:host_deck/server/core/http/result.dart';
import 'package:host_deck/server/core/ssh/ssh_service.dart';
import 'package:host_deck/server/features/code_server/code_server_manager.dart';
import 'package:host_deck/server/features/code_server/code_server_models.dart';
import 'package:host_deck/server/features/code_server/ide_package_store.dart';

class CodeServerController {
  static const _maxPackageBytes = 600 * 1024 * 1024;
  static final _log = Logger('CodeServerController');

  final CodeServerManager _manager;
  final IdePackageStore _packages;
  final SshService _sshService;

  CodeServerController({
    required CodeServerManager manager,
    required IdePackageStore packages,
    required SshService sshService,
  }) : _manager = manager,
       _packages = packages,
       _sshService = sshService;

  Future<Response> listPackages(Request request) async {
    try {
      final packages = await _packages.list();
      return Result.ok(packages.map(_packageJson).toList());
    } catch (error) {
      return Result.fail(500, error.toString());
    }
  }

  Future<Response> uploadPackage(Request request) async {
    final version = request.url.queryParameters['version']?.trim();
    final arch = request.url.queryParameters['arch']?.trim();
    if (version == null || !RegExp(r'^\d+\.\d+\.\d+$').hasMatch(version)) {
      return Result.fail(400, '缺少合法的 version 参数（例如 4.143.1）。');
    }
    if (arch != 'amd64' && arch != 'arm64') {
      return Result.fail(400, 'arch 必须是 amd64 或 arm64。');
    }

    final tempDir = Directory('${_packages.root.path}/tmp');
    await tempDir.create(recursive: true);
    final temp = File(
      '${tempDir.path}/upload-${DateTime.now().microsecondsSinceEpoch}.tar.gz',
    );

    var received = 0;
    IOSink? sink;
    try {
      sink = temp.openWrite();
      await for (final chunk in request.read()) {
        received += chunk.length;
        if (received > _maxPackageBytes) {
          throw const FormatException('离线包超过 600MB 限制。');
        }
        sink.add(chunk);
      }
      await sink.flush();
      await sink.close();
      sink = null;

      final package = await _packages.importFile(
        temp,
        version: version,
        arch: arch!,
      );
      if (temp.existsSync()) temp.deleteSync();
      return Result.ok(_packageJson(package));
    } catch (error) {
      try {
        await sink?.close();
      } catch (_) {}
      if (temp.existsSync()) temp.deleteSync();
      return Result.fail(500, '上传离线包失败：$error');
    }
  }

  Future<Response> deletePackage(Request request, String id) async {
    try {
      await _packages.delete(id);
      return Result.ok({'success': true});
    } catch (error) {
      return Result.fail(500, error.toString());
    }
  }

  Future<Response> scanPackages(Request request) async {
    try {
      final packages = await _packages.scan();
      return Result.ok({'packages': packages.map(_packageJson).toList()});
    } catch (error) {
      return Result.fail(500, error.toString());
    }
  }

  Future<Response> status(Request request, String connectionId) async {
    if (_sshService.metadataFor(connectionId) == null) {
      // 统一返回 HTTP 200：Cascade 会继续处理 404，导致 JSON 被 SPA fallback 吞掉。
      return Result.ok({
        'connectionId': connectionId,
        'connection': null,
        'preflight': null,
        'preflightError': 'SSH 连接不存在或已断开。',
        'packages': const [],
        'session': null,
      });
    }
    IdePreflight? preflight;
    String? preflightError;
    try {
      preflight = await _manager.preflight(connectionId);
    } catch (error) {
      preflightError = error.toString();
    }
    final session = _manager.sessionFor(connectionId);
    final packages = await _packages.list();
    return Result.ok({
      'connectionId': connectionId,
      'connection': _connectionJson(connectionId),
      'preflight': preflight?.toJson(),
      'preflightError': preflightError,
      'packages': packages.map(_packageJson).toList(),
      'session': session == null ? null : _sessionJson(session),
    });
  }

  Future<Response> install(Request request, String connectionId) async {
    try {
      final data = await _readJson(request);
      final packageId = data['packageId'];
      if (packageId is! String || packageId.trim().isEmpty) {
        return Result.fail(400, '缺少 packageId。');
      }
      final session = await _manager.install(
        connectionId,
        packageId: packageId.trim(),
      );
      return Result.ok(_sessionJson(session));
    } catch (error) {
      _log.warning('code-server 操作失败（connection=$connectionId）：$error');
      return Result.fail(500, _describe(error));
    }
  }

  Future<Response> start(Request request, String connectionId) async {
    try {
      final data = await _readJson(request);
      final folder = data['folder'];
      final session = await _manager.start(
        connectionId,
        folder: folder is String && folder.trim().isNotEmpty
            ? folder.trim()
            : null,
      );
      return Result.ok(_sessionJson(session));
    } catch (error) {
      _log.warning('code-server 操作失败（connection=$connectionId）：$error');
      return Result.fail(500, _describe(error));
    }
  }

  Future<Response> stop(Request request, String connectionId) async {
    try {
      final session = await _manager.stop(connectionId);
      return Result.ok(_sessionJson(session));
    } catch (error) {
      _log.warning('code-server 操作失败（connection=$connectionId）：$error');
      return Result.fail(500, _describe(error));
    }
  }

  Future<Response> uninstall(Request request, String connectionId) async {
    try {
      await _manager.uninstall(connectionId);
      return Result.ok(null);
    } catch (error) {
      _log.warning('code-server 卸载失败（connection=$connectionId）：$error');
      return Result.fail(500, _describe(error));
    }
  }

  Map<String, dynamic> _sessionJson(IdeSessionSnapshot session) => {
    ...session.toJson(),
    'url': session.state == IdeSessionState.running
        ? '/ide/${session.id}/'
        : null,
  };

  Map<String, dynamic>? _connectionJson(String connectionId) {
    final metadata = _sshService.metadataFor(connectionId);
    if (metadata == null) return null;
    return {
      'host': metadata.host,
      'port': metadata.port,
      'username': metadata.username,
    };
  }

  Map<String, dynamic> _packageJson(IdePackage package) => {
    ...package.toJson(),
    'path': null,
  };

  Future<Map<String, dynamic>> _readJson(Request request) async {
    final body = await request.readAsString();
    if (body.trim().isEmpty) return const {};
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('请求体必须是 JSON 对象。');
    }
    return decoded;
  }

  String _describe(Object error) =>
      error is StateError ? error.message.toString() : error.toString();
}
