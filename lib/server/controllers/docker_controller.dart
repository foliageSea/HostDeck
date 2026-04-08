import 'dart:typed_data';
import 'dart:convert';
import 'package:shelf/shelf.dart';
import '../services/ssh_service.dart';
import '../services/docker_service.dart';
import '../models/ssh_session.dart';
import '../models/result.dart';

class DockerController {
  final SshService _sshService;
  final DockerService _dockerService;

  DockerController(this._sshService, this._dockerService);

  String _shellQuote(String value) {
    // Safe for POSIX sh: wrap in single quotes and escape embedded single quotes.
    return "'${value.replaceAll("'", "'\\''")}'";
  }

  /// 创建一个新的终端会话并进入容器 Shell
  ///
  /// 返回: { sessionId }
  Future<Response> createContainerShellSession(
    Request request,
    String id,
  ) async {
    final sessionId = request.url.queryParameters['sessionId'];
    if (sessionId == null) {
      return Result.fail(400, 'Missing sessionId');
    }

    final session = _sshService.getSession(sessionId);
    if (session == null) {
      return Result.fail(404, 'Session not found');
    }

    try {
      final shellSession = await _sshService.createShell(session.connectionId);
      final shell = shellSession.shell;
      if (shell == null) {
        return Result.fail(500, 'Shell not available');
      }

      // Prefer bash if present, fallback to sh.
      final safeId = _shellQuote(id);
      final cmd = 'docker exec -it $safeId bash || docker exec -it $safeId sh';
      shell.write(Uint8List.fromList(utf8.encode('$cmd\n')));

      return Result.ok({'sessionId': shellSession.id});
    } catch (e) {
      return Result.fail(500, e.toString());
    }
  }

  /// 检查 Docker 可用性
  Future<Response> checkDocker(Request request) async {
    final sessionId = request.url.queryParameters['sessionId'];
    if (sessionId == null) {
      return Result.fail(400, 'Missing sessionId');
    }

    final session = _sshService.getSession(sessionId);
    if (session == null) {
      return Result.fail(404, 'Session not found');
    }

    try {
      final available = await _dockerService.isDockerAvailable(session);
      return Result.ok({'available': available});
    } catch (e) {
      return Result.ok({'available': false});
    }
  }

  /// 获取容器列表
  Future<Response> listContainers(Request request) async {
    final sessionId = request.url.queryParameters['sessionId'];
    if (sessionId == null) {
      return Result.fail(400, 'Missing sessionId');
    }

    final session = _sshService.getSession(sessionId);
    if (session == null) {
      return Result.fail(404, 'Session not found');
    }

    try {
      final containers = await _dockerService.listContainers(session);
      return Result.ok(containers.map((c) => c.toJson()).toList());
    } catch (e) {
      return Result.fail(500, e.toString());
    }
  }

  /// 获取镜像列表
  Future<Response> listImages(Request request) async {
    final sessionId = request.url.queryParameters['sessionId'];
    if (sessionId == null) {
      return Result.fail(400, 'Missing sessionId');
    }

    final session = _sshService.getSession(sessionId);
    if (session == null) {
      return Result.fail(404, 'Session not found');
    }

    try {
      final images = await _dockerService.listImages(session);
      return Result.ok(images.map((i) => i.toJson()).toList());
    } catch (e) {
      return Result.fail(500, e.toString());
    }
  }

  /// 启动容器
  Future<Response> startContainer(Request request, String id) async {
    return _handleContainerAction(request, id, _dockerService.startContainer);
  }

  /// 停止容器
  Future<Response> stopContainer(Request request, String id) async {
    return _handleContainerAction(request, id, _dockerService.stopContainer);
  }

  /// 重启容器
  Future<Response> restartContainer(Request request, String id) async {
    return _handleContainerAction(request, id, _dockerService.restartContainer);
  }

  /// 暂停容器
  Future<Response> pauseContainer(Request request, String id) async {
    return _handleContainerAction(request, id, _dockerService.pauseContainer);
  }

  /// 取消暂停容器
  Future<Response> unpauseContainer(Request request, String id) async {
    return _handleContainerAction(request, id, _dockerService.unpauseContainer);
  }

  /// 重命名容器
  Future<Response> renameContainer(Request request, String id) async {
    final sessionId = request.url.queryParameters['sessionId'];
    if (sessionId == null) {
      return Result.fail(400, 'Missing sessionId');
    }

    final session = _sshService.getSession(sessionId);
    if (session == null) {
      return Result.fail(404, 'Session not found');
    }

    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final newName = data['newName']?.toString().trim() ?? '';
      if (newName.isEmpty) {
        return Result.fail(400, 'newName is required');
      }

      await _dockerService.renameContainer(session, id, newName);
      return Result.ok({'success': true});
    } catch (e) {
      return Result.fail(500, e.toString());
    }
  }

  /// 删除容器
  Future<Response> removeContainer(Request request, String id) async {
    final sessionId = request.url.queryParameters['sessionId'];
    final force = request.url.queryParameters['force'] == 'true';

    if (sessionId == null) {
      return Result.fail(400, 'Missing sessionId');
    }

    final session = _sshService.getSession(sessionId);
    if (session == null) {
      return Result.fail(404, 'Session not found');
    }

    try {
      await _dockerService.removeContainer(session, id, force: force);
      return Result.ok({'success': true});
    } catch (e) {
      return Result.fail(500, e.toString());
    }
  }

  /// 获取容器日志
  Future<Response> getContainerLogs(Request request) async {
    final sessionId = request.url.queryParameters['sessionId'];
    final containerId = request.url.queryParameters['containerId'];
    final tail = _parseTail(request.url.queryParameters['tail']);
    final timestamps = request.url.queryParameters['timestamps'] == 'true';

    if (sessionId == null || containerId == null) {
      return Result.fail(400, 'Missing sessionId or containerId');
    }

    final session = _sshService.getSession(sessionId);
    if (session == null) {
      return Result.fail(404, 'Session not found');
    }

    try {
      final logs = await _dockerService.getContainerLogs(
        session,
        containerId,
        tail: tail,
        timestamps: timestamps,
      );
      return Result.ok({'logs': logs});
    } catch (e) {
      return Result.fail(500, e.toString());
    }
  }

  /// 获取容器 inspect 详情
  Future<Response> inspectContainer(Request request, String id) async {
    final sessionId = request.url.queryParameters['sessionId'];
    if (sessionId == null) {
      return Result.fail(400, 'Missing sessionId');
    }

    final session = _sshService.getSession(sessionId);
    if (session == null) {
      return Result.fail(404, 'Session not found');
    }

    try {
      final detail = await _dockerService.inspectContainer(session, id);
      return Result.ok(detail);
    } catch (e) {
      return Result.fail(500, e.toString());
    }
  }

  /// 获取容器资源信息
  Future<Response> getContainerStats(Request request, String id) async {
    final sessionId = request.url.queryParameters['sessionId'];
    if (sessionId == null) {
      return Result.fail(400, 'Missing sessionId');
    }

    final session = _sshService.getSession(sessionId);
    if (session == null) {
      return Result.fail(404, 'Session not found');
    }

    try {
      final stats = await _dockerService.getContainerStats(session, id);
      return Result.ok(stats);
    } catch (e) {
      return Result.fail(500, e.toString());
    }
  }

  /// 批量获取容器诊断信息
  Future<Response> getContainerDiagnostics(Request request) async {
    final sessionId = request.url.queryParameters['sessionId'];
    if (sessionId == null) {
      return Result.fail(400, 'Missing sessionId');
    }

    final session = _sshService.getSession(sessionId);
    if (session == null) {
      return Result.fail(404, 'Session not found');
    }

    final ids = await _parseIds(request);
    if (ids == null) {
      return Result.fail(400, 'Missing or invalid containerIds');
    }

    try {
      final diagnostics = await _dockerService.getContainerDiagnostics(
        session,
        ids,
      );
      return Result.ok(diagnostics);
    } catch (e) {
      return Result.fail(500, e.toString());
    }
  }

  /// 删除镜像
  Future<Response> removeImage(Request request, String id) async {
    final sessionId = request.url.queryParameters['sessionId'];
    final force = request.url.queryParameters['force'] == 'true';

    if (sessionId == null) {
      return Result.fail(400, 'Missing sessionId');
    }

    final session = _sshService.getSession(sessionId);
    if (session == null) {
      return Result.fail(404, 'Session not found');
    }

    try {
      await _dockerService.removeImage(session, id, force: force);
      return Result.ok({'success': true});
    } catch (e) {
      return Result.fail(500, e.toString());
    }
  }

  /// 拉取镜像
  Future<Response> pullImage(Request request) async {
    final sessionId = request.url.queryParameters['sessionId'];
    if (sessionId == null) {
      return Result.fail(400, 'Missing sessionId');
    }

    final session = _sshService.getSession(sessionId);
    if (session == null) {
      return Result.fail(404, 'Session not found');
    }

    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final image = data['image']?.toString().trim() ?? '';
      if (image.isEmpty) {
        return Result.fail(400, 'image is required');
      }

      final output = await _dockerService.pullImage(session, image);
      return Result.ok({'success': true, 'output': output});
    } catch (e) {
      return Result.fail(500, e.toString());
    }
  }

  /// 镜像重新打标签
  Future<Response> tagImage(Request request) async {
    final sessionId = request.url.queryParameters['sessionId'];
    if (sessionId == null) {
      return Result.fail(400, 'Missing sessionId');
    }

    final session = _sshService.getSession(sessionId);
    if (session == null) {
      return Result.fail(404, 'Session not found');
    }

    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final sourceImage = data['sourceImage']?.toString().trim() ?? '';
      final targetImage = data['targetImage']?.toString().trim() ?? '';
      if (sourceImage.isEmpty || targetImage.isEmpty) {
        return Result.fail(400, 'sourceImage and targetImage are required');
      }

      await _dockerService.tagImage(session, sourceImage, targetImage);
      return Result.ok({'success': true});
    } catch (e) {
      return Result.fail(500, e.toString());
    }
  }

  /// 镜像历史
  Future<Response> getImageHistory(Request request, String id) async {
    final sessionId = request.url.queryParameters['sessionId'];
    if (sessionId == null) {
      return Result.fail(400, 'Missing sessionId');
    }

    final session = _sshService.getSession(sessionId);
    if (session == null) {
      return Result.fail(404, 'Session not found');
    }

    try {
      final history = await _dockerService.getImageHistory(session, id);
      return Result.ok(history);
    } catch (e) {
      return Result.fail(500, e.toString());
    }
  }

  /// 获取镜像引用容器
  Future<Response> getImageContainers(Request request, String id) async {
    final sessionId = request.url.queryParameters['sessionId'];
    if (sessionId == null) {
      return Result.fail(400, 'Missing sessionId');
    }

    final session = _sshService.getSession(sessionId);
    if (session == null) {
      return Result.fail(404, 'Session not found');
    }

    try {
      final containers = await _dockerService.getImageContainers(session, id);
      return Result.ok(containers);
    } catch (e) {
      return Result.fail(500, e.toString());
    }
  }

  /// 创建容器
  Future<Response> createContainer(Request request) async {
    final sessionId = request.url.queryParameters['sessionId'];
    if (sessionId == null) {
      return Result.fail(400, 'Missing sessionId');
    }

    final session = _sshService.getSession(sessionId);
    if (session == null) {
      return Result.fail(404, 'Session not found');
    }

    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final result = await _dockerService.createContainer(session, data);
      return Result.ok(result);
    } catch (e) {
      return Result.fail(500, e.toString());
    }
  }

  /// 快速重建容器
  Future<Response> recreateContainer(Request request, String id) async {
    final sessionId = request.url.queryParameters['sessionId'];
    if (sessionId == null) {
      return Result.fail(400, 'Missing sessionId');
    }

    final session = _sshService.getSession(sessionId);
    if (session == null) {
      return Result.fail(404, 'Session not found');
    }

    try {
      final result = await _dockerService.recreateContainer(session, id);
      return Result.ok(result);
    } catch (e) {
      return Result.fail(500, e.toString());
    }
  }

  /// 批量启动容器
  Future<Response> batchStartContainers(Request request) async {
    return _handleBatchContainerAction(
      request,
      _dockerService.batchStartContainers,
      successMessage: 'Containers started',
    );
  }

  /// 批量停止容器
  Future<Response> batchStopContainers(Request request) async {
    return _handleBatchContainerAction(
      request,
      _dockerService.batchStopContainers,
      successMessage: 'Containers stopped',
    );
  }

  /// 批量删除已停止容器
  Future<Response> removeStoppedContainers(Request request) async {
    final sessionId = request.url.queryParameters['sessionId'];
    if (sessionId == null) {
      return Result.fail(400, 'Missing sessionId');
    }

    final session = _sshService.getSession(sessionId);
    if (session == null) {
      return Result.fail(404, 'Session not found');
    }

    try {
      final removedCount = await _dockerService.removeStoppedContainers(
        session,
      );
      return Result.ok({'success': true, 'removedCount': removedCount});
    } catch (e) {
      return Result.fail(500, e.toString());
    }
  }

  /// 清理镜像
  Future<Response> pruneImages(Request request) async {
    final sessionId = request.url.queryParameters['sessionId'];
    if (sessionId == null) {
      return Result.fail(400, 'Missing sessionId');
    }

    final session = _sshService.getSession(sessionId);
    if (session == null) {
      return Result.fail(404, 'Session not found');
    }

    bool includeUnused = false;
    try {
      final body = await request.readAsString();
      if (body.trim().isNotEmpty) {
        final data = jsonDecode(body) as Map<String, dynamic>;
        includeUnused = data['includeUnused'] == true;
      }
    } catch (_) {
      includeUnused = false;
    }

    try {
      final output = await _dockerService.pruneImages(
        session,
        includeUnused: includeUnused,
      );
      return Result.ok({'success': true, 'output': output});
    } catch (e) {
      return Result.fail(500, e.toString());
    }
  }

  // Helper method
  Future<Response> _handleContainerAction(
    Request request,
    String containerId,
    Future<void> Function(SshSession, String) action,
  ) async {
    final sessionId = request.url.queryParameters['sessionId'];
    if (sessionId == null) {
      return Result.fail(400, 'Missing sessionId');
    }

    final session = _sshService.getSession(sessionId);
    if (session == null) {
      return Result.fail(404, 'Session not found');
    }

    try {
      await action(session, containerId);
      return Result.ok({'success': true});
    } catch (e) {
      return Result.fail(500, e.toString());
    }
  }

  Future<Response> _handleBatchContainerAction(
    Request request,
    Future<int> Function(SshSession, List<String>) action, {
    required String successMessage,
  }) async {
    final sessionId = request.url.queryParameters['sessionId'];
    if (sessionId == null) {
      return Result.fail(400, 'Missing sessionId');
    }

    final session = _sshService.getSession(sessionId);
    if (session == null) {
      return Result.fail(404, 'Session not found');
    }

    final ids = await _parseIds(request);
    if (ids == null) {
      return Result.fail(400, 'Missing or invalid containerIds');
    }
    if (ids.isEmpty) {
      return Result.fail(400, 'containerIds cannot be empty');
    }

    try {
      final processed = await action(session, ids);
      return Result.ok({
        'success': true,
        'processed': processed,
        'message': successMessage,
      });
    } catch (e) {
      return Result.fail(500, e.toString());
    }
  }

  Future<List<String>?> _parseIds(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final ids = data['containerIds'];
      if (ids is! List) {
        return null;
      }

      return ids
          .map((id) => id.toString().trim())
          .where((id) => id.isNotEmpty)
          .toList();
    } catch (_) {
      return null;
    }
  }

  int _parseTail(String? value) {
    final parsed = int.tryParse(value ?? '200') ?? 200;
    if (parsed < 1) return 100;
    if (parsed > 5000) return 5000;
    return parsed;
  }
}
