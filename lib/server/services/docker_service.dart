import 'dart:convert';
import 'package:logging/logging.dart';
import '../models/ssh_session.dart';
import '../models/docker_container.dart';
import '../models/docker_image.dart';
import '../repositories/ssh_repository.dart';

class DockerService {
  final SshRepository _repository;
  final _log = Logger('DockerService');

  DockerService(this._repository);

  /// 获取容器列表
  Future<List<DockerContainer>> listContainers(SshSession session) async {
    try {
      final output = await _repository.exec(
        session,
        'docker ps -a --format "{{json .}}"',
      );

      final lines = output.trim().split('\n');
      final containers = <DockerContainer>[];

      for (final line in lines) {
        if (line.isEmpty) continue;
        try {
          final json = _parseDockerJson(line);
          containers.add(
            DockerContainer(
              id: json['ID'] ?? json['Id'] ?? '',
              name: (json['Names'] ?? '').toString().split(',')[0],
              image: json['Image'] ?? '',
              status: json['Status'] ?? '',
              state: json['State'] ?? '',
              ports: _parsePorts(json['Ports']),
              createdAt: _parseCreatedAt(json['CreatedAt']),
            ),
          );
        } catch (e) {
          _log.warning('Failed to parse container: $e');
        }
      }

      return containers;
    } catch (e) {
      _log.severe('Failed to list containers: $e');
      throw Exception('Failed to list containers: $e');
    }
  }

  /// 获取镜像列表
  Future<List<DockerImage>> listImages(SshSession session) async {
    try {
      final usedImageIds = await _getUsedImageIds(session);
      final output = await _repository.exec(
        session,
        'docker images --format "{{json .}}"',
      );

      final lines = output.trim().split('\n');
      final images = <DockerImage>[];

      for (final line in lines) {
        if (line.isEmpty) continue;
        try {
          final json = _parseDockerJson(line);
          final id = (json['ID'] ?? '').toString();
          final repository = (json['Repository'] ?? '').toString();
          final tag = (json['Tag'] ?? '').toString();
          final dangling = repository == '<none>' && tag == '<none>';
          images.add(
            DockerImage(
              id: id,
              repository: repository,
              tag: tag,
              size: json['Size'] ?? '',
              createdAt: _parseCreatedAt(json['CreatedAt']),
              dangling: dangling,
              inUse: _isImageInUse(id, usedImageIds),
            ),
          );
        } catch (e) {
          _log.warning('Failed to parse image: $e');
        }
      }

      return images;
    } catch (e) {
      _log.severe('Failed to list images: $e');
      throw Exception('Failed to list images: $e');
    }
  }

  /// 启动容器
  Future<void> startContainer(SshSession session, String containerId) async {
    final safeContainerId = _shellQuote(containerId);
    await _repository.exec(session, 'docker start $safeContainerId');
  }

  /// 停止容器
  Future<void> stopContainer(SshSession session, String containerId) async {
    final safeContainerId = _shellQuote(containerId);
    await _repository.exec(session, 'docker stop $safeContainerId');
  }

  /// 重启容器
  Future<void> restartContainer(SshSession session, String containerId) async {
    final safeContainerId = _shellQuote(containerId);
    await _repository.exec(session, 'docker restart $safeContainerId');
  }

  /// 暂停容器
  Future<void> pauseContainer(SshSession session, String containerId) async {
    final safeContainerId = _shellQuote(containerId);
    await _repository.exec(session, 'docker pause $safeContainerId');
  }

  /// 取消暂停容器
  Future<void> unpauseContainer(SshSession session, String containerId) async {
    final safeContainerId = _shellQuote(containerId);
    await _repository.exec(session, 'docker unpause $safeContainerId');
  }

  /// 重命名容器
  Future<void> renameContainer(
    SshSession session,
    String containerId,
    String newName,
  ) async {
    final safeContainerId = _shellQuote(containerId);
    final safeNewName = _shellQuote(newName);
    await _repository.exec(
      session,
      'docker rename $safeContainerId $safeNewName',
    );
  }

  /// 删除容器
  Future<void> removeContainer(
    SshSession session,
    String containerId, {
    bool force = false,
  }) async {
    final forceFlag = force ? '-f' : '';
    final safeContainerId = _shellQuote(containerId);
    await _repository.exec(session, 'docker rm $forceFlag $safeContainerId');
  }

  /// 获取容器日志
  Future<String> getContainerLogs(
    SshSession session,
    String containerId, {
    int tail = 100,
    bool timestamps = false,
  }) async {
    final safeContainerId = _shellQuote(containerId);
    final timestampFlag = timestamps ? '-t' : '';
    return await _repository.exec(
      session,
      'docker logs $timestampFlag --tail $tail $safeContainerId',
    );
  }

  /// 删除镜像
  Future<void> removeImage(
    SshSession session,
    String imageId, {
    bool force = false,
  }) async {
    final forceFlag = force ? '-f' : '';
    final safeImageId = _shellQuote(imageId);
    await _repository.exec(session, 'docker rmi $forceFlag $safeImageId');
  }

  /// 拉取镜像
  Future<String> pullImage(SshSession session, String imageRef) async {
    final safeImageRef = _shellQuote(imageRef);
    return await _repository.exec(session, 'docker pull $safeImageRef');
  }

  /// 镜像重新打标签
  Future<void> tagImage(
    SshSession session,
    String sourceImage,
    String targetImage,
  ) async {
    final safeSourceImage = _shellQuote(sourceImage);
    final safeTargetImage = _shellQuote(targetImage);
    await _repository.exec(
      session,
      'docker tag $safeSourceImage $safeTargetImage',
    );
  }

  /// 获取镜像历史
  Future<List<Map<String, dynamic>>> getImageHistory(
    SshSession session,
    String imageId,
  ) async {
    final safeImageId = _shellQuote(imageId);
    final output = await _repository.exec(
      session,
      'docker image history --no-trunc --format "{{json .}}" $safeImageId',
    );

    final lines = output.split('\n').map((line) => line.trim());
    final items = <Map<String, dynamic>>[];
    for (final line in lines) {
      if (line.isEmpty) continue;
      try {
        final json = _parseDockerJson(line);
        items.add({
          'id': (json['ID'] ?? '').toString(),
          'createdSince': (json['CreatedSince'] ?? '').toString(),
          'createdAt': (json['CreatedAt'] ?? '').toString(),
          'createdBy': (json['CreatedBy'] ?? '').toString(),
          'size': (json['Size'] ?? '').toString(),
          'comment': (json['Comment'] ?? '').toString(),
        });
      } catch (_) {
        // ignore invalid row
      }
    }

    return items;
  }

  /// 获取引用镜像的容器
  Future<List<Map<String, dynamic>>> getImageContainers(
    SshSession session,
    String imageId,
  ) async {
    final safeImageId = _shellQuote(imageId);
    final output = await _repository.exec(
      session,
      'docker ps -a --filter ancestor=$safeImageId --format "{{json .}}"',
    );

    final lines = output.split('\n').map((line) => line.trim());
    final containers = <Map<String, dynamic>>[];
    for (final line in lines) {
      if (line.isEmpty) continue;
      try {
        final json = _parseDockerJson(line);
        containers.add({
          'id': (json['ID'] ?? '').toString(),
          'name': (json['Names'] ?? '').toString(),
          'image': (json['Image'] ?? '').toString(),
          'state': (json['State'] ?? '').toString(),
          'status': (json['Status'] ?? '').toString(),
        });
      } catch (_) {
        // ignore invalid row
      }
    }
    return containers;
  }

  /// 创建容器
  Future<Map<String, dynamic>> createContainer(
    SshSession session,
    Map<String, dynamic> payload,
  ) async {
    final image = payload['image']?.toString().trim() ?? '';
    if (image.isEmpty) {
      throw Exception('image is required');
    }

    final command = _buildDockerCreateCommand(payload);
    final output = await _repository.exec(session, command);
    final containerId = output
        .split('\n')
        .map((line) => line.trim())
        .firstWhere((line) => line.isNotEmpty, orElse: () => '');

    final startAfterCreate = payload['start'] == true;
    if (startAfterCreate) {
      final safeContainerId = _shellQuote(containerId);
      await _repository.exec(session, 'docker start $safeContainerId');
    }

    return {'containerId': containerId, 'started': startAfterCreate};
  }

  /// 快速重建容器（基础版）
  Future<Map<String, dynamic>> recreateContainer(
    SshSession session,
    String containerId,
  ) async {
    final inspect = await inspectContainer(session, containerId);
    final nameRaw = inspect['Name']?.toString() ?? '';
    final name = nameRaw.startsWith('/') ? nameRaw.substring(1) : nameRaw;
    final state =
        inspect['State'] as Map<String, dynamic>? ?? <String, dynamic>{};
    final wasRunning = state['Running'] == true;

    final payload = _buildCreatePayloadFromInspect(inspect);
    final createCommand = _buildDockerCreateCommand(payload);

    final safeContainerId = _shellQuote(containerId);
    await _repository.exec(session, 'docker rm -f $safeContainerId');
    final createOutput = await _repository.exec(session, createCommand);

    final newContainerId = createOutput
        .split('\n')
        .map((line) => line.trim())
        .firstWhere((line) => line.isNotEmpty, orElse: () => '');

    if (wasRunning) {
      if (newContainerId.isNotEmpty) {
        final safeNewContainerId = _shellQuote(newContainerId);
        await _repository.exec(session, 'docker start $safeNewContainerId');
      }
    }

    return {
      'oldContainerId': containerId,
      'newContainerId': newContainerId,
      'name': name,
      'started': wasRunning,
    };
  }

  /// 批量启动容器
  Future<int> batchStartContainers(
    SshSession session,
    List<String> containerIds,
  ) async {
    final ids = _normalizeIds(containerIds);
    for (final id in ids) {
      await startContainer(session, id);
    }
    return ids.length;
  }

  /// 批量停止容器
  Future<int> batchStopContainers(
    SshSession session,
    List<String> containerIds,
  ) async {
    final ids = _normalizeIds(containerIds);
    for (final id in ids) {
      await stopContainer(session, id);
    }
    return ids.length;
  }

  /// 批量删除已停止容器
  Future<int> removeStoppedContainers(SshSession session) async {
    final output = await _repository.exec(
      session,
      'docker ps -a --filter "status=exited" --format "{{.ID}}"',
    );
    final ids = output
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

    for (final id in ids) {
      await removeContainer(session, id);
    }

    return ids.length;
  }

  /// 清理镜像
  Future<String> pruneImages(
    SshSession session, {
    bool includeUnused = false,
  }) async {
    final allFlag = includeUnused ? '-a' : '';
    return await _repository.exec(session, 'docker image prune $allFlag -f');
  }

  /// 检查 Docker 是否可用
  Future<bool> isDockerAvailable(SshSession session) async {
    try {
      await _repository.exec(session, 'docker --version');
      return true;
    } catch (e) {
      return false;
    }
  }

  /// 获取容器 inspect 详情
  Future<Map<String, dynamic>> inspectContainer(
    SshSession session,
    String containerId,
  ) async {
    final safeContainerId = _shellQuote(containerId);
    final output = await _repository.exec(
      session,
      'docker inspect $safeContainerId',
    );

    final parsed = jsonDecode(output);
    if (parsed is List &&
        parsed.isNotEmpty &&
        parsed.first is Map<String, dynamic>) {
      return parsed.first as Map<String, dynamic>;
    }
    throw Exception('Invalid docker inspect output');
  }

  /// 获取容器资源信息（docker stats --no-stream）
  Future<Map<String, dynamic>> getContainerStats(
    SshSession session,
    String containerId,
  ) async {
    final safeContainerId = _shellQuote(containerId);
    final output = await _repository.exec(
      session,
      'docker stats --no-stream --format "{{json .}}" $safeContainerId',
    );

    final line = output
        .split('\n')
        .map((value) => value.trim())
        .firstWhere((value) => value.isNotEmpty, orElse: () => '');
    if (line.isEmpty) {
      throw Exception('Container stats is empty');
    }

    final json = _parseDockerJson(line);
    return {
      'id': (json['ID'] ?? '').toString(),
      'name': (json['Name'] ?? '').toString(),
      'cpuPercent': (json['CPUPerc'] ?? '').toString(),
      'memPercent': (json['MemPerc'] ?? '').toString(),
      'memUsage': (json['MemUsage'] ?? '').toString(),
      'netIO': (json['NetIO'] ?? '').toString(),
      'blockIO': (json['BlockIO'] ?? '').toString(),
      'pids': (json['PIDs'] ?? '').toString(),
    };
  }

  /// 获取容器诊断信息（重启次数、健康状态、退出码）
  Future<List<Map<String, dynamic>>> getContainerDiagnostics(
    SshSession session,
    List<String> containerIds,
  ) async {
    final ids = _normalizeIds(containerIds);
    final results = <Map<String, dynamic>>[];

    for (final id in ids) {
      try {
        final inspect = await inspectContainer(session, id);
        final state =
            inspect['State'] as Map<String, dynamic>? ?? <String, dynamic>{};
        final health = state['Health'] as Map<String, dynamic>?;
        results.add({
          'containerId': id,
          'restartCount': _toInt(state['RestartCount']),
          'healthStatus': health?['Status']?.toString() ?? '',
          'exitCode': _toInt(state['ExitCode']),
        });
      } catch (_) {
        results.add({
          'containerId': id,
          'restartCount': 0,
          'healthStatus': '',
          'exitCode': 0,
        });
      }
    }

    return results;
  }

  // Helper methods
  Map<String, dynamic> _parseDockerJson(String line) {
    return jsonDecode(line) as Map<String, dynamic>;
  }

  String _shellQuote(String value) {
    return "'${value.replaceAll("'", "'\\''")}'";
  }

  List<String> _normalizeIds(List<String> ids) {
    return ids
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
  }

  Future<Set<String>> _getUsedImageIds(SshSession session) async {
    try {
      final output = await _repository.exec(
        session,
        'docker ps -a --format "{{.ImageID}}"',
      );

      return output
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toSet();
    } catch (_) {
      return <String>{};
    }
  }

  bool _isImageInUse(String imageId, Set<String> usedImageIds) {
    if (imageId.isEmpty) return false;
    final normalizedImageId = _normalizeImageId(imageId);

    for (final usedId in usedImageIds) {
      final normalizedUsedId = _normalizeImageId(usedId);
      if (normalizedUsedId == normalizedImageId ||
          normalizedUsedId.startsWith(normalizedImageId) ||
          normalizedImageId.startsWith(normalizedUsedId)) {
        return true;
      }
    }
    return false;
  }

  String _normalizeImageId(String id) {
    return id.trim().toLowerCase().replaceFirst('sha256:', '');
  }

  List<String> _parsePorts(dynamic ports) {
    if (ports == null) return [];
    if (ports is List) return ports.cast<String>();
    return ports.toString().split(',').map((s) => s.trim()).toList();
  }

  DateTime? _parseCreatedAt(dynamic createdAt) {
    if (createdAt == null) return null;
    final value = createdAt.toString().trim();
    if (value.isEmpty) return null;

    var parsed = DateTime.tryParse(value);
    if (parsed != null) return parsed;

    final withoutTzName = value.replaceFirst(RegExp(r'\s+[A-Za-z]+$'), '');
    parsed = DateTime.tryParse(withoutTzName);
    if (parsed != null) return parsed;

    final normalizedOffset = withoutTzName.replaceFirstMapped(
      RegExp(r'([+-]\d{2})(\d{2})$'),
      (match) => '${match.group(1)}:${match.group(2)}',
    );
    parsed = DateTime.tryParse(normalizedOffset);
    return parsed;
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _buildDockerCreateCommand(Map<String, dynamic> payload) {
    final args = <String>['docker create'];

    final image = payload['image']?.toString().trim() ?? '';
    if (image.isEmpty) {
      throw Exception('image is required');
    }

    final name = payload['name']?.toString().trim() ?? '';
    if (name.isNotEmpty) {
      args.add('--name ${_shellQuote(name)}');
    }

    final restartPolicy = payload['restartPolicy']?.toString().trim() ?? '';
    if (restartPolicy.isNotEmpty && restartPolicy != 'no') {
      args.add('--restart ${_shellQuote(restartPolicy)}');
    }

    final ports = payload['ports'];
    if (ports is List) {
      for (final item in ports) {
        final port = item.toString().trim();
        if (port.isNotEmpty) {
          args.add('-p ${_shellQuote(port)}');
        }
      }
    }

    final env = payload['env'];
    if (env is List) {
      for (final item in env) {
        final value = item.toString().trim();
        if (value.isNotEmpty) {
          args.add('-e ${_shellQuote(value)}');
        }
      }
    }

    final volumes = payload['volumes'];
    if (volumes is List) {
      for (final item in volumes) {
        final value = item.toString().trim();
        if (value.isNotEmpty) {
          args.add('-v ${_shellQuote(value)}');
        }
      }
    }

    final entrypoint = payload['entrypoint'];
    if (entrypoint is List) {
      final values = entrypoint
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList();
      if (values.isNotEmpty) {
        final encoded = jsonEncode(values);
        args.add('--entrypoint ${_shellQuote(encoded)}');
      }
    }

    args.add(_shellQuote(image));

    final cmd = payload['cmd'];
    if (cmd is List) {
      final values = cmd
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty);
      for (final value in values) {
        args.add(_shellQuote(value));
      }
    }

    return args.join(' ');
  }

  Map<String, dynamic> _buildCreatePayloadFromInspect(
    Map<String, dynamic> inspect,
  ) {
    final config =
        inspect['Config'] as Map<String, dynamic>? ?? <String, dynamic>{};
    final hostConfig =
        inspect['HostConfig'] as Map<String, dynamic>? ?? <String, dynamic>{};
    final nameRaw = inspect['Name']?.toString() ?? '';
    final name = nameRaw.startsWith('/') ? nameRaw.substring(1) : nameRaw;

    final restartName =
        (hostConfig['RestartPolicy'] as Map<String, dynamic>? ??
                <String, dynamic>{})['Name']
            ?.toString()
            .trim();

    final ports = <String>[];
    final portBindings =
        hostConfig['PortBindings'] as Map<String, dynamic>? ??
        <String, dynamic>{};
    portBindings.forEach((containerPort, bindings) {
      if (bindings is List && bindings.isNotEmpty) {
        for (final binding in bindings) {
          if (binding is Map<String, dynamic>) {
            final hostIp = (binding['HostIp'] ?? '').toString();
            final hostPort = (binding['HostPort'] ?? '').toString();
            if (hostPort.isEmpty) continue;
            if (hostIp.isNotEmpty && hostIp != '0.0.0.0') {
              ports.add('$hostIp:$hostPort:$containerPort');
            } else {
              ports.add('$hostPort:$containerPort');
            }
          }
        }
      }
    });

    final volumes = <String>[];
    final mounts = inspect['Mounts'];
    if (mounts is List) {
      for (final mount in mounts) {
        if (mount is Map<String, dynamic>) {
          final source = (mount['Source'] ?? '').toString();
          final destination = (mount['Destination'] ?? '').toString();
          if (source.isEmpty || destination.isEmpty) continue;
          final rw = mount['RW'] != false;
          final suffix = rw ? '' : ':ro';
          volumes.add('$source:$destination$suffix');
        }
      }
    }

    return {
      'image': config['Image']?.toString() ?? '',
      'name': name,
      'ports': ports,
      'env':
          (config['Env'] as List?)?.map((e) => e.toString()).toList() ??
          <String>[],
      'volumes': volumes,
      'restartPolicy': (restartName == null || restartName.isEmpty)
          ? 'no'
          : restartName,
      'entrypoint':
          (config['Entrypoint'] as List?)?.map((e) => e.toString()).toList() ??
          <String>[],
      'cmd':
          (config['Cmd'] as List?)?.map((e) => e.toString()).toList() ??
          <String>[],
    };
  }
}
