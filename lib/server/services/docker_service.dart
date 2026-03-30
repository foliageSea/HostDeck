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
          containers.add(DockerContainer(
            id: json['ID'] ?? json['Id'] ?? '',
            name: (json['Names'] ?? '').toString().split(',')[0],
            image: json['Image'] ?? '',
            status: json['Status'] ?? '',
            state: json['State'] ?? '',
            ports: _parsePorts(json['Ports']),
            createdAt: _parseCreatedAt(json['CreatedAt']),
          ));
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
          images.add(DockerImage(
            id: json['ID'] ?? '',
            repository: json['Repository'] ?? '',
            tag: json['Tag'] ?? '',
            size: json['Size'] ?? '',
            createdAt: _parseCreatedAt(json['CreatedAt']),
          ));
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
    await _repository.exec(session, 'docker start $containerId');
  }

  /// 停止容器
  Future<void> stopContainer(SshSession session, String containerId) async {
    await _repository.exec(session, 'docker stop $containerId');
  }

  /// 重启容器
  Future<void> restartContainer(SshSession session, String containerId) async {
    await _repository.exec(session, 'docker restart $containerId');
  }

  /// 删除容器
  Future<void> removeContainer(SshSession session, String containerId, {bool force = false}) async {
    final forceFlag = force ? '-f' : '';
    await _repository.exec(session, 'docker rm $forceFlag $containerId');
  }

  /// 获取容器日志
  Future<String> getContainerLogs(SshSession session, String containerId, {int tail = 100}) async {
    return await _repository.exec(
      session,
      'docker logs --tail $tail $containerId',
    );
  }

  /// 删除镜像
  Future<void> removeImage(SshSession session, String imageId, {bool force = false}) async {
    final forceFlag = force ? '-f' : '';
    await _repository.exec(session, 'docker rmi $forceFlag $imageId');
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

  // Helper methods
  Map<String, dynamic> _parseDockerJson(String line) {
    return jsonDecode(line) as Map<String, dynamic>;
  }

  List<String> _parsePorts(dynamic ports) {
    if (ports == null) return [];
    if (ports is List) return ports.cast<String>();
    return ports.toString().split(',').map((s) => s.trim()).toList();
  }

  DateTime? _parseCreatedAt(dynamic createdAt) {
    if (createdAt == null) return null;
    return DateTime.tryParse(createdAt.toString());
  }
}
