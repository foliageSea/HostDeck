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
}
