import 'dart:convert';
import 'dart:typed_data';

import 'package:shelf/shelf.dart';

import '../models/docker_container.dart';
import '../models/result.dart';
import '../models/ssh_session.dart';
import '../services/docker_service.dart';
import '../services/ssh_service.dart';

class DockerController {
  final SshService _sshService;
  final DockerService _dockerService;
  final Map<String, String> _sharedSessionIds = {};
  final Map<String, Future<SshSession>> _pendingSharedSessions = {};

  DockerController(this._sshService, this._dockerService);

  Future<SshSession> _getOrCreateSharedSession(String connectionId) async {
    final existingSessionId = _sharedSessionIds[connectionId];
    if (existingSessionId != null) {
      final existingSession = _sshService.getSession(existingSessionId);
      if (existingSession != null) {
        return existingSession;
      }

      _sharedSessionIds.remove(connectionId);
    }

    final pendingSession = _pendingSharedSessions[connectionId];
    if (pendingSession != null) {
      return pendingSession;
    }

    final nextSession = _sshService
        .createShell(connectionId)
        .then((session) {
          _sharedSessionIds[connectionId] = session.id;
          return session;
        })
        .whenComplete(() {
          _pendingSharedSessions.remove(connectionId);
        });

    _pendingSharedSessions[connectionId] = nextSession;
    return nextSession;
  }

  void _removeSharedSessionById(String sessionId) {
    _sharedSessionIds.removeWhere((_, value) => value == sessionId);
  }

  Future<SshSession> _resolveSession(Request request) async {
    final sessionId = request.url.queryParameters['sessionId'];
    if (sessionId != null) {
      final session = _sshService.getSession(sessionId);
      if (session != null) {
        return session;
      }

      throw StateError('Session not found');
    }

    final connectionId = request.url.queryParameters['connectionId'];
    if (connectionId == null) {
      throw ArgumentError('Missing connectionId or sessionId');
    }

    return _getOrCreateSharedSession(connectionId);
  }

  Response _sessionErrorResponse(Object error) {
    if (error is ArgumentError) {
      return Result.fail(400, error.message?.toString() ?? error.toString());
    }

    if (error is StateError) {
      return Result.fail(404, error.message);
    }

    return Result.fail(500, error.toString());
  }

  Future<Response> _withSession(
    Request request,
    Future<Response> Function(SshSession session) action,
  ) async {
    late final SshSession session;
    try {
      session = await _resolveSession(request);
    } catch (error) {
      return _sessionErrorResponse(error);
    }

    return action(session);
  }

  Future<Response> createSession(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final connectionId = data['connectionId'];

      if (connectionId == null) {
        return Result.fail(400, 'Missing connectionId');
      }

      final session = await _getOrCreateSharedSession(connectionId.toString());

      return Result.ok({'sessionId': session.id});
    } on SshSessionLimitExceeded catch (e) {
      return Result.fail(429, '最多只能创建 ${e.maxSessions} 个 SSH 会话。');
    } catch (e) {
      return Result.fail(500, e.toString());
    }
  }

  Future<Response> closeSession(Request request) async {
    try {
      final sessionId = request.url.queryParameters['sessionId'];
      final connectionId = request.url.queryParameters['connectionId'];

      String? targetSessionId = sessionId;
      if (targetSessionId == null && connectionId != null) {
        targetSessionId = _sharedSessionIds.remove(connectionId);
      }

      if (targetSessionId == null) {
        return Result.fail(400, 'Missing connectionId or sessionId');
      }

      _removeSharedSessionById(targetSessionId);
      await _sshService.closeSession(targetSessionId);

      return Result.ok('Session closed');
    } catch (e) {
      return Result.fail(500, e.toString());
    }
  }

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
    return _withSession(request, (session) async {
      try {
        final shellSession = await _sshService.createShell(
          session.connectionId,
        );
        final shell = shellSession.shell;
        if (shell == null) {
          return Result.fail(500, 'Shell not available');
        }

        // Prefer bash if present, fallback to sh.
        final safeId = _shellQuote(id);
        final cmd =
            'docker exec -it $safeId bash || docker exec -it $safeId sh';
        shell.write(Uint8List.fromList(utf8.encode('$cmd\n')));

        return Result.ok({'sessionId': shellSession.id});
      } on SshSessionLimitExceeded catch (e) {
        return Result.fail(429, '最多只能创建 ${e.maxSessions} 个 SSH 会话。');
      } catch (e) {
        return Result.fail(500, e.toString());
      }
    });
  }

  /// 检查 Docker 可用性
  Future<Response> checkDocker(Request request) async {
    return _withSession(request, (session) async {
      try {
        final available = await _dockerService.isDockerAvailable(session);
        return Result.ok({'available': available});
      } catch (e) {
        return Result.ok({'available': false});
      }
    });
  }

  /// 检查 Docker Compose 可用性
  Future<Response> checkCompose(Request request) async {
    return _withSession(request, (session) async {
      try {
        final available = await _dockerService.isComposeAvailable(session);
        return Result.ok({'available': available});
      } catch (e) {
        return Result.ok({'available': false});
      }
    });
  }

  /// 获取 Compose 项目列表
  Future<Response> listComposeProjects(Request request) async {
    return _withSession(request, (session) async {
      try {
        final projects = await _dockerService.listComposeProjects(session);
        return Result.ok(projects);
      } catch (e) {
        return Result.fail(500, e.toString());
      }
    });
  }

  /// 创建 Compose 项目
  Future<Response> createComposeProject(Request request) async {
    return _withSession(request, (session) async {
      try {
        final body = await request.readAsString();
        final data = jsonDecode(body) as Map<String, dynamic>;
        final result = await _dockerService.createComposeProject(session, data);
        return Result.ok(result);
      } catch (e) {
        return Result.fail(500, e.toString());
      }
    });
  }

  /// 获取 Compose 项目服务
  Future<Response> listComposeServices(Request request) async {
    final payload = await _parseComposeProjectPayload(request);
    if (payload == null) {
      return Result.fail(400, 'Missing or invalid compose project payload');
    }

    return _withSession(request, (session) async {
      try {
        final services = await _dockerService.listComposeServices(
          session,
          projectName: payload.projectName,
          configFiles: payload.configFiles,
          workingDir: payload.workingDir,
        );
        return Result.ok(services);
      } catch (e) {
        return Result.fail(500, e.toString());
      }
    });
  }

  Future<Response> upComposeProject(Request request) async {
    return _handleComposeProjectAction(
      request,
      _dockerService.upComposeProject,
    );
  }

  Future<Response> stopComposeProject(Request request) async {
    return _handleComposeProjectAction(
      request,
      _dockerService.stopComposeProject,
    );
  }

  Future<Response> restartComposeProject(Request request) async {
    return _handleComposeProjectAction(
      request,
      _dockerService.restartComposeProject,
    );
  }

  Future<Response> downComposeProject(Request request) async {
    return _handleComposeProjectAction(
      request,
      _dockerService.downComposeProject,
    );
  }

  Future<Response> getComposeLogs(Request request) async {
    final tail = _parseTail(request.url.queryParameters['tail']);
    final payload = await _parseComposeProjectPayload(request);
    if (payload == null) {
      return Result.fail(400, 'Missing or invalid compose project payload');
    }

    return _withSession(request, (session) async {
      try {
        final logs = await _dockerService.getComposeLogs(
          session,
          projectName: payload.projectName,
          configFiles: payload.configFiles,
          workingDir: payload.workingDir,
          tail: tail,
        );
        return Result.ok({'logs': logs});
      } catch (e) {
        return Result.fail(500, e.toString());
      }
    });
  }

  /// 获取容器列表
  Future<Response> listContainers(Request request) async {
    final pagination = _parsePagination(request);
    final statusFilter = request.url.queryParameters['status'] ?? 'all';
    return _withSession(request, (session) async {
      try {
        final containers = await _dockerService.listContainers(session);
        final filteredContainers = containers
            .where(
              (container) => _matchesContainerStatus(container, statusFilter),
            )
            .toList();
        return Result.ok(
          _pageResponse(
            filteredContainers,
            pagination,
            (container) => container.toJson(),
            summary: {
              'total': containers.length,
              'running': containers
                  .where((container) => container.state == 'running')
                  .length,
              'stopped': containers
                  .where((container) => container.state != 'running')
                  .length,
            },
          ),
        );
      } catch (e) {
        return Result.fail(500, e.toString());
      }
    });
  }

  /// 获取镜像列表
  Future<Response> listImages(Request request) async {
    final pagination = _parsePagination(request);
    return _withSession(request, (session) async {
      try {
        final images = await _dockerService.listImages(session);
        return Result.ok(
          _pageResponse(
            images,
            pagination,
            (image) => image.toJson(),
            summary: {
              'total': images.length,
              'dangling': images.where((image) => image.dangling).length,
            },
          ),
        );
      } catch (e) {
        return Result.fail(500, e.toString());
      }
    });
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
    return _withSession(request, (session) async {
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
    });
  }

  /// 删除容器
  Future<Response> removeContainer(Request request, String id) async {
    final force = request.url.queryParameters['force'] == 'true';

    return _withSession(request, (session) async {
      try {
        await _dockerService.removeContainer(session, id, force: force);
        return Result.ok({'success': true});
      } catch (e) {
        return Result.fail(500, e.toString());
      }
    });
  }

  /// 获取容器日志
  Future<Response> getContainerLogs(Request request) async {
    final containerId = request.url.queryParameters['containerId'];
    final tail = _parseTail(request.url.queryParameters['tail']);
    final timestamps = request.url.queryParameters['timestamps'] == 'true';

    if (containerId == null) {
      return Result.fail(400, 'Missing containerId');
    }

    return _withSession(request, (session) async {
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
    });
  }

  /// 获取容器 inspect 详情
  Future<Response> inspectContainer(Request request, String id) async {
    return _withSession(request, (session) async {
      try {
        final detail = await _dockerService.inspectContainer(session, id);
        return Result.ok(detail);
      } catch (e) {
        return Result.fail(500, e.toString());
      }
    });
  }

  /// 获取容器资源信息
  Future<Response> getContainerStats(Request request, String id) async {
    return _withSession(request, (session) async {
      try {
        final stats = await _dockerService.getContainerStats(session, id);
        return Result.ok(stats);
      } catch (e) {
        return Result.fail(500, e.toString());
      }
    });
  }

  /// 批量获取容器诊断信息
  Future<Response> getContainerDiagnostics(Request request) async {
    final ids = await _parseIds(request);
    if (ids == null) {
      return Result.fail(400, 'Missing or invalid containerIds');
    }

    return _withSession(request, (session) async {
      try {
        final diagnostics = await _dockerService.getContainerDiagnostics(
          session,
          ids,
        );
        return Result.ok(diagnostics);
      } catch (e) {
        return Result.fail(500, e.toString());
      }
    });
  }

  /// 删除镜像
  Future<Response> removeImage(Request request, String id) async {
    final force = request.url.queryParameters['force'] == 'true';

    return _withSession(request, (session) async {
      try {
        await _dockerService.removeImage(session, id, force: force);
        return Result.ok({'success': true});
      } catch (e) {
        return Result.fail(500, e.toString());
      }
    });
  }

  /// 拉取镜像
  Future<Response> pullImage(Request request) async {
    return _withSession(request, (session) async {
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
    });
  }

  /// 镜像重新打标签
  Future<Response> tagImage(Request request) async {
    return _withSession(request, (session) async {
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
    });
  }

  /// 镜像历史
  Future<Response> getImageHistory(Request request, String id) async {
    return _withSession(request, (session) async {
      try {
        final history = await _dockerService.getImageHistory(session, id);
        return Result.ok(history);
      } catch (e) {
        return Result.fail(500, e.toString());
      }
    });
  }

  /// 获取镜像创建容器默认配置
  Future<Response> getImageCreateDefaults(Request request, String id) async {
    return _withSession(request, (session) async {
      try {
        final defaults = await _dockerService.getImageCreateDefaults(
          session,
          id,
        );
        return Result.ok(defaults);
      } catch (e) {
        return Result.fail(500, e.toString());
      }
    });
  }

  /// 获取镜像引用容器
  Future<Response> getImageContainers(Request request, String id) async {
    return _withSession(request, (session) async {
      try {
        final containers = await _dockerService.getImageContainers(session, id);
        return Result.ok(containers);
      } catch (e) {
        return Result.fail(500, e.toString());
      }
    });
  }

  /// 创建容器
  Future<Response> createContainer(Request request) async {
    return _withSession(request, (session) async {
      try {
        final body = await request.readAsString();
        final data = jsonDecode(body) as Map<String, dynamic>;
        final result = await _dockerService.createContainer(session, data);
        return Result.ok(result);
      } catch (e) {
        return Result.fail(500, e.toString());
      }
    });
  }

  /// 快速重建容器
  Future<Response> recreateContainer(Request request, String id) async {
    return _withSession(request, (session) async {
      try {
        final result = await _dockerService.recreateContainer(session, id);
        return Result.ok(result);
      } catch (e) {
        return Result.fail(500, e.toString());
      }
    });
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
    return _withSession(request, (session) async {
      try {
        final removedCount = await _dockerService.removeStoppedContainers(
          session,
        );
        return Result.ok({'success': true, 'removedCount': removedCount});
      } catch (e) {
        return Result.fail(500, e.toString());
      }
    });
  }

  /// 清理镜像
  Future<Response> pruneImages(Request request) async {
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

    return _withSession(request, (session) async {
      try {
        final output = await _dockerService.pruneImages(
          session,
          includeUnused: includeUnused,
        );
        return Result.ok({'success': true, 'output': output});
      } catch (e) {
        return Result.fail(500, e.toString());
      }
    });
  }

  // Helper method
  Future<Response> _handleContainerAction(
    Request request,
    String containerId,
    Future<void> Function(SshSession, String) action,
  ) async {
    return _withSession(request, (session) async {
      try {
        await action(session, containerId);
        return Result.ok({'success': true});
      } catch (e) {
        return Result.fail(500, e.toString());
      }
    });
  }

  Future<Response> _handleBatchContainerAction(
    Request request,
    Future<int> Function(SshSession, List<String>) action, {
    required String successMessage,
  }) async {
    final ids = await _parseIds(request);
    if (ids == null) {
      return Result.fail(400, 'Missing or invalid containerIds');
    }
    if (ids.isEmpty) {
      return Result.fail(400, 'containerIds cannot be empty');
    }

    return _withSession(request, (session) async {
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
    });
  }

  Future<Response> _handleComposeProjectAction(
    Request request,
    Future<String> Function(
      SshSession, {
      required String projectName,
      required List<String> configFiles,
      String? workingDir,
    })
    action,
  ) async {
    final payload = await _parseComposeProjectPayload(request);
    if (payload == null) {
      return Result.fail(400, 'Missing or invalid compose project payload');
    }

    return _withSession(request, (session) async {
      try {
        final output = await action(
          session,
          projectName: payload.projectName,
          configFiles: payload.configFiles,
          workingDir: payload.workingDir,
        );
        return Result.ok({'success': true, 'output': output});
      } catch (e) {
        return Result.fail(500, e.toString());
      }
    });
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

  Future<_ComposeProjectPayload?> _parseComposeProjectPayload(
    Request request,
  ) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final projectName = data['projectName']?.toString().trim() ?? '';
      final workingDir = data['workingDir']?.toString().trim();
      final configFilesValue = data['configFiles'];
      final configFiles = configFilesValue is List
          ? configFilesValue
                .map((item) => item.toString().trim())
                .where((item) => item.isNotEmpty)
                .toList()
          : <String>[];

      if (projectName.isEmpty || configFiles.isEmpty) {
        return null;
      }

      return _ComposeProjectPayload(
        projectName: projectName,
        configFiles: configFiles,
        workingDir: workingDir == null || workingDir.isEmpty
            ? null
            : workingDir,
      );
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

  _PaginationParams _parsePagination(Request request) {
    final query = request.url.queryParameters;
    final page = int.tryParse(query['page'] ?? '') ?? 1;
    final pageSize = int.tryParse(query['pageSize'] ?? '') ?? 8;

    return _PaginationParams(
      page: page < 1 ? 1 : page,
      pageSize: pageSize < 1 ? 8 : (pageSize > 100 ? 100 : pageSize),
    );
  }

  Map<String, dynamic> _pageResponse<T>(
    List<T> items,
    _PaginationParams pagination,
    Object? Function(T item) toJson, {
    Map<String, dynamic> summary = const {},
  }) {
    final total = items.length;
    final totalPages = total == 0
        ? 0
        : ((total + pagination.pageSize - 1) ~/ pagination.pageSize);
    final page = totalPages == 0
        ? 1
        : (pagination.page > totalPages ? totalPages : pagination.page);
    final start = (page - 1) * pagination.pageSize;
    final pageItems = start >= total
        ? <T>[]
        : items.skip(start).take(pagination.pageSize).toList();

    return {
      'items': pageItems.map(toJson).toList(),
      'total': total,
      'page': page,
      'pageSize': pagination.pageSize,
      'totalPages': totalPages,
      if (summary.isNotEmpty) 'summary': summary,
    };
  }

  bool _matchesContainerStatus(DockerContainer container, String statusFilter) {
    final filter = statusFilter.trim().toLowerCase();
    final state = container.state.toLowerCase();
    final status = container.status.toLowerCase();

    if (filter.isEmpty || filter == 'all') {
      return true;
    }
    if (filter == 'running') {
      return state == 'running' && !status.contains('paused');
    }
    if (filter == 'stopped') {
      return state != 'running';
    }
    if (filter == 'paused') {
      return status.contains('paused');
    }
    if (filter == 'restarting') {
      return state == 'restarting' || status.contains('restarting');
    }
    if (filter == 'exited') {
      return state == 'exited' || status.contains('exited');
    }

    return true;
  }
}

class _PaginationParams {
  final int page;
  final int pageSize;

  const _PaginationParams({required this.page, required this.pageSize});
}

class _ComposeProjectPayload {
  final String projectName;
  final List<String> configFiles;
  final String? workingDir;

  const _ComposeProjectPayload({
    required this.projectName,
    required this.configFiles,
    this.workingDir,
  });
}
