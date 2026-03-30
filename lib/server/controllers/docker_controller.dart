import 'package:shelf/shelf.dart';
import '../services/ssh_service.dart';
import '../services/docker_service.dart';
import '../models/ssh_session.dart';
import '../models/result.dart';

class DockerController {
  final SshService _sshService;
  final DockerService _dockerService;

  DockerController(this._sshService, this._dockerService);

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
    final tail = int.tryParse(request.url.queryParameters['tail'] ?? '100') ?? 100;

    if (sessionId == null || containerId == null) {
      return Result.fail(400, 'Missing sessionId or containerId');
    }

    final session = _sshService.getSession(sessionId);
    if (session == null) {
      return Result.fail(404, 'Session not found');
    }

    try {
      final logs = await _dockerService.getContainerLogs(session, containerId, tail: tail);
      return Result.ok({'logs': logs});
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
}
