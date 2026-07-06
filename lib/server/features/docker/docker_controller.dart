import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:shelf/shelf.dart';
import 'package:shelf_multipart/shelf_multipart.dart';

import 'package:host_deck/server/core/http/result.dart';
import 'package:host_deck/server/core/ssh/shared_ssh_session_resolver.dart';
import 'package:host_deck/server/core/ssh/ssh_service.dart';
import 'package:host_deck/server/core/ssh/ssh_session.dart';
import 'package:host_deck/server/features/docker/docker_container.dart';
import 'package:host_deck/server/features/docker/docker_image.dart';
import 'package:host_deck/server/features/docker/docker_service.dart';
import 'package:host_deck/server/features/operation_logs/operation_log_service.dart';

class DockerController {
  final SshService _sshService;
  final DockerService _dockerService;
  final OperationLogService _operationLogService;
  final SharedSshSessionResolver _sessionResolver;

  DockerController(
    this._sshService,
    this._dockerService,
    this._operationLogService,
  ) : _sessionResolver = SharedSshSessionResolver(
        _sshService,
        type: SharedSshSessionType.shell,
      );

  Future<SshSession> _resolveSession(Request request) async {
    return _sessionResolver.resolveFromRequest(request);
  }

  Response _sessionErrorResponse(Object error) {
    return _sessionResolver.errorResponse(error);
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

      final session = await _sessionResolver.createForConnection(
        connectionId.toString(),
      );

      return Result.ok({'sessionId': session.id});
    } on SshSessionLimitExceeded catch (e) {
      return Result.fail(429, '最多只能创建 ${e.maxSessions} 个 SSH 会话。');
    } catch (e) {
      return Result.fail(500, e.toString());
    }
  }

  Future<Response> closeSession(Request request) async {
    try {
      await _sessionResolver.closeFromRequest(request);

      return Result.ok('Session closed');
    } catch (e) {
      return Result.fail(500, e.toString());
    }
  }

  String _shellQuote(String value) {
    // Safe for POSIX sh: wrap in single quotes and escape embedded single quotes.
    return "'${value.replaceAll("'", "'\\''")}'";
  }

  String _downloadFilenameForImage(String imageRef) {
    final sanitized = imageRef
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');

    return '${sanitized.isEmpty ? 'docker-image' : sanitized}.tar';
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
      actionName: 'composeUp',
    );
  }

  Future<Response> stopComposeProject(Request request) async {
    return _handleComposeProjectAction(
      request,
      _dockerService.stopComposeProject,
      actionName: 'composeStop',
    );
  }

  Future<Response> restartComposeProject(Request request) async {
    return _handleComposeProjectAction(
      request,
      _dockerService.restartComposeProject,
      actionName: 'composeRestart',
    );
  }

  Future<Response> downComposeProject(Request request) async {
    return _handleComposeProjectAction(
      request,
      _dockerService.downComposeProject,
      actionName: 'composeDown',
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
    final keyword = request.url.queryParameters['keyword'] ?? '';
    return _withSession(request, (session) async {
      try {
        final containers = await _dockerService.listContainers(session);
        final filteredContainers = containers
            .where(
              (container) => _matchesContainerStatus(container, statusFilter),
            )
            .where((container) => _matchesContainerKeyword(container, keyword))
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
    final keyword = request.url.queryParameters['keyword'] ?? '';
    return _withSession(request, (session) async {
      try {
        final images = await _dockerService.listImages(session);
        final filteredImages = images
            .where((image) => _matchesImageKeyword(image, keyword))
            .toList();
        return Result.ok(
          _pageResponse(
            filteredImages,
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

  /// 获取网络列表
  Future<Response> listNetworks(Request request) async {
    return _withSession(request, (session) async {
      try {
        final networks = await _dockerService.listNetworks(session);
        return Result.ok(networks.map((item) => item.toJson()).toList());
      } catch (e) {
        return Result.fail(500, e.toString());
      }
    });
  }

  /// 获取存储卷列表
  Future<Response> listVolumes(Request request) async {
    return _withSession(request, (session) async {
      try {
        final volumes = await _dockerService.listVolumes(session);
        return Result.ok(volumes.map((item) => item.toJson()).toList());
      } catch (e) {
        return Result.fail(500, e.toString());
      }
    });
  }

  /// 启动容器
  Future<Response> startContainer(Request request, String id) async {
    return _handleContainerAction(
      request,
      id,
      _dockerService.startContainer,
      actionName: 'containerStart',
    );
  }

  /// 停止容器
  Future<Response> stopContainer(Request request, String id) async {
    return _handleContainerAction(
      request,
      id,
      _dockerService.stopContainer,
      actionName: 'containerStop',
    );
  }

  /// 重启容器
  Future<Response> restartContainer(Request request, String id) async {
    return _handleContainerAction(
      request,
      id,
      _dockerService.restartContainer,
      actionName: 'containerRestart',
    );
  }

  /// 暂停容器
  Future<Response> pauseContainer(Request request, String id) async {
    return _handleContainerAction(
      request,
      id,
      _dockerService.pauseContainer,
      actionName: 'containerPause',
    );
  }

  /// 取消暂停容器
  Future<Response> unpauseContainer(Request request, String id) async {
    return _handleContainerAction(
      request,
      id,
      _dockerService.unpauseContainer,
      actionName: 'containerUnpause',
    );
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
        _recordDockerSuccess(
          'containerRename',
          id,
          session.connectionId,
          detail: {'newName': newName},
        );
        return Result.ok({'success': true});
      } catch (e) {
        _recordDockerFailure('containerRename', id, session.connectionId, e);
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
        _recordDockerSuccess(
          'containerRemove',
          id,
          session.connectionId,
          detail: {'force': force},
        );
        return Result.ok({'success': true});
      } catch (e) {
        _recordDockerFailure('containerRemove', id, session.connectionId, e);
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

  /// 获取网络 inspect 详情
  Future<Response> inspectNetwork(Request request, String id) async {
    return _withSession(request, (session) async {
      try {
        final detail = await _dockerService.inspectNetwork(session, id);
        return Result.ok(detail);
      } catch (e) {
        return Result.fail(500, e.toString());
      }
    });
  }

  /// 获取存储卷 inspect 详情
  Future<Response> inspectVolume(Request request, String name) async {
    return _withSession(request, (session) async {
      try {
        final detail = await _dockerService.inspectVolume(session, name);
        return Result.ok(detail);
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
        _recordDockerSuccess(
          'imageRemove',
          id,
          session.connectionId,
          detail: {'force': force},
        );
        return Result.ok({'success': true});
      } catch (e) {
        _recordDockerFailure('imageRemove', id, session.connectionId, e);
        return Result.fail(500, e.toString());
      }
    });
  }

  /// 创建网络
  Future<Response> createNetwork(Request request) async {
    return _withSession(request, (session) async {
      try {
        final body = await request.readAsString();
        final data = jsonDecode(body) as Map<String, dynamic>;
        final result = await _dockerService.createNetwork(session, data);
        _recordDockerSuccess(
          'networkCreate',
          result['id']?.toString() ?? data['name']?.toString() ?? 'network',
          session.connectionId,
          detail: {'name': data['name']},
        );
        return Result.ok(result);
      } catch (e) {
        _recordDockerFailure(
          'networkCreate',
          'network',
          session.connectionId,
          e,
        );
        return Result.fail(500, e.toString());
      }
    });
  }

  /// 创建存储卷
  Future<Response> createVolume(Request request) async {
    return _withSession(request, (session) async {
      try {
        final body = await request.readAsString();
        final data = jsonDecode(body) as Map<String, dynamic>;
        final result = await _dockerService.createVolume(session, data);
        _recordDockerSuccess(
          'volumeCreate',
          result['name']?.toString() ?? data['name']?.toString() ?? 'volume',
          session.connectionId,
          detail: {'name': data['name']},
        );
        return Result.ok(result);
      } catch (e) {
        _recordDockerFailure('volumeCreate', 'volume', session.connectionId, e);
        return Result.fail(500, e.toString());
      }
    });
  }

  /// 删除网络
  Future<Response> removeNetwork(Request request, String id) async {
    return _withSession(request, (session) async {
      try {
        await _dockerService.removeNetwork(session, id);
        _recordDockerSuccess('networkRemove', id, session.connectionId);
        return Result.ok({'success': true});
      } catch (e) {
        _recordDockerFailure('networkRemove', id, session.connectionId, e);
        return Result.fail(500, e.toString());
      }
    });
  }

  /// 删除存储卷
  Future<Response> removeVolume(Request request, String name) async {
    return _withSession(request, (session) async {
      try {
        await _dockerService.removeVolume(session, name);
        _recordDockerSuccess('volumeRemove', name, session.connectionId);
        return Result.ok({'success': true});
      } catch (e) {
        _recordDockerFailure('volumeRemove', name, session.connectionId, e);
        return Result.fail(500, e.toString());
      }
    });
  }

  /// 连接容器到网络
  Future<Response> connectNetwork(Request request, String id) async {
    final payload = await _parseNetworkContainerPayload(request);
    if (payload == null) {
      return Result.fail(400, 'Missing or invalid network container payload');
    }

    return _withSession(request, (session) async {
      try {
        await _dockerService.connectNetwork(session, id, payload.container);
        _recordDockerSuccess(
          'networkConnect',
          id,
          session.connectionId,
          detail: {'container': payload.container},
        );
        return Result.ok({'success': true});
      } catch (e) {
        _recordDockerFailure('networkConnect', id, session.connectionId, e);
        return Result.fail(500, e.toString());
      }
    });
  }

  /// 从网络断开容器
  Future<Response> disconnectNetwork(Request request, String id) async {
    final payload = await _parseNetworkContainerPayload(request);
    if (payload == null) {
      return Result.fail(400, 'Missing or invalid network container payload');
    }

    return _withSession(request, (session) async {
      try {
        await _dockerService.disconnectNetwork(
          session,
          id,
          payload.container,
          force: payload.force,
        );
        _recordDockerSuccess(
          'networkDisconnect',
          id,
          session.connectionId,
          detail: {'container': payload.container, 'force': payload.force},
        );
        return Result.ok({'success': true});
      } catch (e) {
        _recordDockerFailure('networkDisconnect', id, session.connectionId, e);
        return Result.fail(500, e.toString());
      }
    });
  }

  /// 清理未使用网络
  Future<Response> pruneNetworks(Request request) async {
    return _withSession(request, (session) async {
      try {
        final deleted = await _dockerService.pruneNetworks(session);
        _recordDockerSuccess(
          'networkPrune',
          'networks',
          session.connectionId,
          detail: {'deletedCount': deleted.length},
        );
        return Result.ok({
          'success': true,
          'deleted': deleted,
          'deletedCount': deleted.length,
        });
      } catch (e) {
        _recordDockerFailure(
          'networkPrune',
          'networks',
          session.connectionId,
          e,
        );
        return Result.fail(500, e.toString());
      }
    });
  }

  /// 清理未使用存储卷
  Future<Response> pruneVolumes(Request request) async {
    return _withSession(request, (session) async {
      try {
        final deleted = await _dockerService.pruneVolumes(session);
        _recordDockerSuccess(
          'volumePrune',
          'volumes',
          session.connectionId,
          detail: {'deletedCount': deleted.length},
        );
        return Result.ok({
          'success': true,
          'deleted': deleted,
          'deletedCount': deleted.length,
        });
      } catch (e) {
        _recordDockerFailure('volumePrune', 'volumes', session.connectionId, e);
        return Result.fail(500, e.toString());
      }
    });
  }

  /// 清理 Docker 构建缓存
  Future<Response> pruneBuildCache(Request request) async {
    bool includeAll = false;
    try {
      final body = await request.readAsString();
      if (body.trim().isNotEmpty) {
        final data = jsonDecode(body) as Map<String, dynamic>;
        includeAll = data['includeAll'] == true;
      }
    } catch (_) {
      includeAll = false;
    }

    return _withSession(request, (session) async {
      try {
        final result = await _dockerService.pruneBuildCache(
          session,
          includeAll: includeAll,
        );
        _recordDockerSuccess(
          'buildCachePrune',
          'build-cache',
          session.connectionId,
          detail: {'includeAll': includeAll},
        );
        return Result.ok({'success': true, ...result});
      } catch (e) {
        _recordDockerFailure(
          'buildCachePrune',
          'build-cache',
          session.connectionId,
          e,
        );
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
        _recordDockerSuccess('imagePull', image, session.connectionId);
        return Result.ok({'success': true, 'output': output});
      } catch (e) {
        _recordDockerFailure('imagePull', 'image', session.connectionId, e);
        return Result.fail(500, e.toString());
      }
    });
  }

  /// 导入镜像
  Future<Response> importImage(Request request) async {
    return _withSession(request, (session) async {
      try {
        final multipart = request.multipart();
        if (multipart == null) {
          return Result.fail(400, 'Expected multipart request');
        }

        await for (final part in multipart.parts) {
          final contentDisposition = part.headers['content-disposition'];
          if (contentDisposition == null) continue;

          final headerValue = HeaderValue.parse(contentDisposition);
          final partName = headerValue.parameters['name'];
          final filename = headerValue.parameters['filename'];
          if (partName != 'file' || filename == null) continue;

          final output = await _dockerService.importImage(session, part);
          _recordDockerSuccess('imageImport', filename, session.connectionId);
          return Result.ok({'success': true, 'output': output});
        }

        return Result.fail(400, 'image archive is required');
      } catch (e) {
        _recordDockerFailure(
          'imageImport',
          'image archive',
          session.connectionId,
          e,
        );
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
        _recordDockerSuccess(
          'imageTag',
          sourceImage,
          session.connectionId,
          detail: {'targetImage': targetImage},
        );
        return Result.ok({'success': true});
      } catch (e) {
        _recordDockerFailure('imageTag', 'image', session.connectionId, e);
        return Result.fail(500, e.toString());
      }
    });
  }

  /// 导出镜像
  Future<Response> exportImage(Request request, String id) async {
    return _withSession(request, (session) async {
      try {
        final imageRef =
            request.url.queryParameters['image']?.toString().trim() ?? id;
        if (imageRef.isEmpty) {
          return Response.badRequest(body: 'image is required');
        }

        final stream = await _dockerService.exportImage(session, imageRef);
        final filename = _downloadFilenameForImage(imageRef);
        final encodedFilename = Uri.encodeComponent(filename);

        return Response.ok(
          stream,
          headers: {
            'content-type': 'application/x-tar',
            'content-disposition':
                "attachment; filename*=UTF-8''$encodedFilename",
          },
        );
      } catch (e) {
        return Response.internalServerError(body: e.toString());
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
        _recordDockerSuccess(
          'containerCreate',
          result['containerId']?.toString() ??
              data['name']?.toString() ??
              'container',
          session.connectionId,
          detail: {'image': data['image'], 'name': data['name']},
        );
        return Result.ok(result);
      } catch (e) {
        _recordDockerFailure(
          'containerCreate',
          'container',
          session.connectionId,
          e,
        );
        return Result.fail(500, e.toString());
      }
    });
  }

  /// 快速重建容器
  Future<Response> recreateContainer(Request request, String id) async {
    return _withSession(request, (session) async {
      try {
        final result = await _dockerService.recreateContainer(session, id);
        _recordDockerSuccess('containerRecreate', id, session.connectionId);
        return Result.ok(result);
      } catch (e) {
        _recordDockerFailure('containerRecreate', id, session.connectionId, e);
        return Result.fail(500, e.toString());
      }
    });
  }

  /// 批量启动容器
  Future<Response> batchStartContainers(Request request) async {
    return _handleBatchContainerAction(
      request,
      _dockerService.batchStartContainers,
      actionName: 'containerBatchStart',
      successMessage: 'Containers started',
    );
  }

  /// 批量停止容器
  Future<Response> batchStopContainers(Request request) async {
    return _handleBatchContainerAction(
      request,
      _dockerService.batchStopContainers,
      actionName: 'containerBatchStop',
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
        _recordDockerSuccess(
          'containerRemoveStopped',
          'stopped containers',
          session.connectionId,
          detail: {'removedCount': removedCount},
        );
        return Result.ok({'success': true, 'removedCount': removedCount});
      } catch (e) {
        _recordDockerFailure(
          'containerRemoveStopped',
          'stopped containers',
          session.connectionId,
          e,
        );
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
        _recordDockerSuccess(
          'imagePrune',
          'images',
          session.connectionId,
          detail: {'includeUnused': includeUnused},
        );
        return Result.ok({'success': true, 'output': output});
      } catch (e) {
        _recordDockerFailure('imagePrune', 'images', session.connectionId, e);
        return Result.fail(500, e.toString());
      }
    });
  }

  // Helper method
  Future<Response> _handleContainerAction(
    Request request,
    String containerId,
    Future<void> Function(SshSession, String) action, {
    required String actionName,
  }) async {
    return _withSession(request, (session) async {
      try {
        await action(session, containerId);
        _recordDockerSuccess(actionName, containerId, session.connectionId);
        return Result.ok({'success': true});
      } catch (e) {
        _recordDockerFailure(actionName, containerId, session.connectionId, e);
        return Result.fail(500, e.toString());
      }
    });
  }

  Future<Response> _handleBatchContainerAction(
    Request request,
    Future<int> Function(SshSession, List<String>) action, {
    required String actionName,
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
        _recordDockerSuccess(
          actionName,
          '${ids.length} containers',
          session.connectionId,
          detail: {'processed': processed, 'containerIds': ids},
        );
        return Result.ok({
          'success': true,
          'processed': processed,
          'message': successMessage,
        });
      } catch (e) {
        _recordDockerFailure(
          actionName,
          '${ids.length} containers',
          session.connectionId,
          e,
        );
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
    action, {
    required String actionName,
  }) async {
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
        _recordDockerSuccess(
          actionName,
          payload.projectName,
          session.connectionId,
          detail: {
            'workingDir': payload.workingDir,
            'configFiles': payload.configFiles,
          },
        );
        return Result.ok({'success': true, 'output': output});
      } catch (e) {
        _recordDockerFailure(
          actionName,
          payload.projectName,
          session.connectionId,
          e,
        );
        return Result.fail(500, e.toString());
      }
    });
  }

  void _recordDockerSuccess(
    String action,
    String target,
    String connectionId, {
    Map<String, dynamic>? detail,
  }) {
    _operationLogService.success(
      category: 'docker',
      action: action,
      target: target,
      detail: detail,
      connectionId: connectionId,
    );
  }

  void _recordDockerFailure(
    String action,
    String target,
    String connectionId,
    Object error,
  ) {
    _operationLogService.failure(
      category: 'docker',
      action: action,
      target: target,
      connectionId: connectionId,
      error: error,
    );
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

  Future<_NetworkContainerPayload?> _parseNetworkContainerPayload(
    Request request,
  ) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final container = data['container']?.toString().trim() ?? '';
      if (container.isEmpty) {
        return null;
      }

      return _NetworkContainerPayload(
        container: container,
        force: data['force'] == true,
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

  bool _matchesContainerKeyword(DockerContainer container, String keyword) {
    final query = keyword.trim().toLowerCase();
    if (query.isEmpty) {
      return true;
    }

    return [
      container.id,
      container.name,
      container.image,
      container.status,
      container.state,
      ...container.ports,
      ...container.networks.expand(
        (network) => [network.name, network.ipAddress],
      ),
    ].any((value) => value.toLowerCase().contains(query));
  }

  bool _matchesImageKeyword(DockerImage image, String keyword) {
    final query = keyword.trim().toLowerCase();
    if (query.isEmpty) {
      return true;
    }

    return [
      image.id,
      image.repository,
      image.tag,
      image.size,
      image.dangling ? '悬空 dangling' : '',
      image.inUse ? '使用中 in use' : '普通 normal',
    ].any((value) => value.toLowerCase().contains(query));
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

class _NetworkContainerPayload {
  final String container;
  final bool force;

  const _NetworkContainerPayload({
    required this.container,
    required this.force,
  });
}
