import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:logging/logging.dart';

import '../models/docker_container.dart';
import '../models/docker_image.dart';
import '../models/docker_network.dart';
import '../models/docker_volume.dart';
import '../models/ssh_session.dart';
import '../repositories/docker_engine_repository.dart';
import '../repositories/ssh_repository.dart';
import 'docker_engine_mapper.dart';

class DockerService {
  final SshRepository _sshRepository;
  final DockerEngineRepository _engineRepository;
  final DockerEngineMapper _mapper;
  final _log = Logger('DockerService');

  DockerService(
    SshRepository repository, {
    DockerEngineRepository? engineRepository,
    DockerEngineMapper? mapper,
  }) : _sshRepository = repository,
       _engineRepository =
           engineRepository ?? DockerEngineRepository(repository),
       _mapper = mapper ?? DockerEngineMapper();

  String debugDecodeDockerLogs(Uint8List bytes) {
    return _decodeDockerLogs(bytes);
  }

  /// 获取容器列表
  Future<List<DockerContainer>> listContainers(SshSession session) async {
    try {
      final containers = await _engineRepository.requestJsonList(
        session,
        method: 'GET',
        path: '/containers/json',
        queryParameters: {'all': '1'},
      );

      return containers
          .whereType<Map>()
          .map(
            (item) =>
                _mapper.mapContainerSummary(Map<String, dynamic>.from(item)),
          )
          .toList();
    } catch (e) {
      _log.severe('Failed to list containers: $e');
      throw Exception('Failed to list containers: $e');
    }
  }

  /// 获取镜像列表
  Future<List<DockerImage>> listImages(SshSession session) async {
    try {
      final usedImageIds = await _getUsedImageIds(session);
      final images = await _engineRepository.requestJsonList(
        session,
        method: 'GET',
        path: '/images/json',
        queryParameters: {'all': '1'},
      );

      return _mapper.mapImageSummaries(images, usedImageIds);
    } catch (e) {
      _log.severe('Failed to list images: $e');
      throw Exception('Failed to list images: $e');
    }
  }

  /// 获取网络列表
  Future<List<DockerNetwork>> listNetworks(SshSession session) async {
    try {
      final networks = await _engineRepository.requestJsonList(
        session,
        method: 'GET',
        path: '/networks',
      );

      final enrichedNetworks = await Future.wait(
        networks.whereType<Map>().map((item) async {
          final network = Map<String, dynamic>.from(item);
          final networkId = (network['Id'] ?? '').toString();
          if (networkId.isEmpty || network.containsKey('Containers')) {
            return network;
          }

          try {
            final details = await _engineRepository.requestJsonObject(
              session,
              method: 'GET',
              path: '/networks/${Uri.encodeComponent(networkId)}',
            );
            return {...network, ...details};
          } catch (e) {
            _log.warning('Failed to inspect network $networkId: $e');
            return network;
          }
        }),
      );

      return _mapper.mapNetworkSummaries(enrichedNetworks);
    } catch (e) {
      _log.severe('Failed to list networks: $e');
      throw Exception('Failed to list networks: $e');
    }
  }

  /// 获取存储卷列表
  Future<List<DockerVolume>> listVolumes(SshSession session) async {
    try {
      final result = await _engineRepository.requestJsonObject(
        session,
        method: 'GET',
        path: '/volumes',
      );

      final volumes = result['Volumes'] as List? ?? <dynamic>[];
      return _mapper.mapVolumeSummaries(volumes);
    } catch (e) {
      _log.severe('Failed to list volumes: $e');
      throw Exception('Failed to list volumes: $e');
    }
  }

  /// 启动容器
  Future<void> startContainer(SshSession session, String containerId) async {
    await _engineRepository.request(
      session,
      method: 'POST',
      path: '/containers/$containerId/start',
    );
  }

  /// 停止容器
  Future<void> stopContainer(SshSession session, String containerId) async {
    await _engineRepository.request(
      session,
      method: 'POST',
      path: '/containers/$containerId/stop',
    );
  }

  /// 重启容器
  Future<void> restartContainer(SshSession session, String containerId) async {
    await _engineRepository.request(
      session,
      method: 'POST',
      path: '/containers/$containerId/restart',
    );
  }

  /// 暂停容器
  Future<void> pauseContainer(SshSession session, String containerId) async {
    await _engineRepository.request(
      session,
      method: 'POST',
      path: '/containers/$containerId/pause',
    );
  }

  /// 取消暂停容器
  Future<void> unpauseContainer(SshSession session, String containerId) async {
    await _engineRepository.request(
      session,
      method: 'POST',
      path: '/containers/$containerId/unpause',
    );
  }

  /// 重命名容器
  Future<void> renameContainer(
    SshSession session,
    String containerId,
    String newName,
  ) async {
    await _engineRepository.request(
      session,
      method: 'POST',
      path: '/containers/$containerId/rename',
      queryParameters: {'name': newName},
    );
  }

  /// 删除容器
  Future<void> removeContainer(
    SshSession session,
    String containerId, {
    bool force = false,
  }) async {
    await _engineRepository.request(
      session,
      method: 'DELETE',
      path: '/containers/$containerId',
      queryParameters: {'force': force.toString()},
    );
  }

  /// 获取容器日志
  Future<String> getContainerLogs(
    SshSession session,
    String containerId, {
    int tail = 100,
    bool timestamps = false,
  }) async {
    final logs = await _engineRepository.requestBytes(
      session,
      method: 'GET',
      path: '/containers/$containerId/logs',
      queryParameters: {
        'stdout': '1',
        'stderr': '1',
        'tail': tail.toString(),
        'timestamps': timestamps ? '1' : '0',
      },
    );
    return _decodeDockerLogs(logs);
  }

  /// 删除镜像
  Future<void> removeImage(
    SshSession session,
    String imageId, {
    bool force = false,
  }) async {
    await _engineRepository.request(
      session,
      method: 'DELETE',
      path: '/images/${Uri.encodeComponent(imageId)}',
      queryParameters: {'force': force.toString()},
    );
  }

  /// 获取网络 inspect 详情
  Future<Map<String, dynamic>> inspectNetwork(
    SshSession session,
    String networkId,
  ) async {
    return await _engineRepository.requestJsonObject(
      session,
      method: 'GET',
      path: '/networks/${Uri.encodeComponent(networkId)}',
    );
  }

  /// 获取存储卷 inspect 详情
  Future<Map<String, dynamic>> inspectVolume(
    SshSession session,
    String volumeName,
  ) async {
    return await _engineRepository.requestJsonObject(
      session,
      method: 'GET',
      path: '/volumes/${Uri.encodeComponent(volumeName)}',
    );
  }

  /// 创建网络
  Future<Map<String, dynamic>> createNetwork(
    SshSession session,
    Map<String, dynamic> payload,
  ) async {
    final requestBody = _mapper.buildCreateNetworkRequest(payload);
    final result = await _engineRepository.requestJsonObject(
      session,
      method: 'POST',
      path: '/networks/create',
      body: requestBody,
    );

    return {
      'id': (result['Id'] ?? '').toString(),
      'warning': (result['Warning'] ?? '').toString(),
    };
  }

  /// 创建存储卷
  Future<Map<String, dynamic>> createVolume(
    SshSession session,
    Map<String, dynamic> payload,
  ) async {
    final requestBody = _mapper.buildCreateVolumeRequest(payload);
    final result = await _engineRepository.requestJsonObject(
      session,
      method: 'POST',
      path: '/volumes/create',
      body: requestBody,
    );

    return {
      'name': (result['Name'] ?? '').toString(),
      'mountpoint': (result['Mountpoint'] ?? '').toString(),
      'warning': (result['Warning'] ?? '').toString(),
    };
  }

  /// 删除网络
  Future<void> removeNetwork(SshSession session, String networkId) async {
    await _engineRepository.request(
      session,
      method: 'DELETE',
      path: '/networks/${Uri.encodeComponent(networkId)}',
    );
  }

  /// 删除存储卷
  Future<void> removeVolume(SshSession session, String volumeName) async {
    await _engineRepository.request(
      session,
      method: 'DELETE',
      path: '/volumes/${Uri.encodeComponent(volumeName)}',
    );
  }

  /// 连接容器到网络
  Future<void> connectNetwork(
    SshSession session,
    String networkId,
    String container,
  ) async {
    await _engineRepository.request(
      session,
      method: 'POST',
      path: '/networks/${Uri.encodeComponent(networkId)}/connect',
      body: {'Container': container},
    );
  }

  /// 从网络断开容器
  Future<void> disconnectNetwork(
    SshSession session,
    String networkId,
    String container, {
    bool force = false,
  }) async {
    await _engineRepository.request(
      session,
      method: 'POST',
      path: '/networks/${Uri.encodeComponent(networkId)}/disconnect',
      body: {'Container': container, 'Force': force},
    );
  }

  /// 清理未使用网络
  Future<List<String>> pruneNetworks(SshSession session) async {
    final result = await _engineRepository.requestJsonObject(
      session,
      method: 'POST',
      path: '/networks/prune',
    );
    return (result['NetworksDeleted'] as List?)
            ?.map((item) => item.toString())
            .where((item) => item.isNotEmpty)
            .toList() ??
        <String>[];
  }

  /// 清理未使用存储卷
  Future<List<String>> pruneVolumes(SshSession session) async {
    final result = await _engineRepository.requestJsonObject(
      session,
      method: 'POST',
      path: '/volumes/prune',
    );
    return (result['VolumesDeleted'] as List?)
            ?.map((item) => item.toString())
            .where((item) => item.isNotEmpty)
            .toList() ??
        <String>[];
  }

  /// 拉取镜像
  Future<String> pullImage(SshSession session, String imageRef) async {
    final parsed = _splitImageReference(imageRef);
    return await _engineRepository.requestText(
      session,
      method: 'POST',
      path: '/images/create',
      queryParameters: {
        'fromImage': parsed.repository,
        if (parsed.tag.isNotEmpty) 'tag': parsed.tag,
      },
    );
  }

  /// 镜像重新打标签
  Future<void> tagImage(
    SshSession session,
    String sourceImage,
    String targetImage,
  ) async {
    final parsedTarget = _splitImageReference(targetImage);
    await _engineRepository.request(
      session,
      method: 'POST',
      path: '/images/${Uri.encodeComponent(sourceImage)}/tag',
      queryParameters: {
        'repo': parsedTarget.repository,
        if (parsedTarget.tag.isNotEmpty) 'tag': parsedTarget.tag,
      },
    );
  }

  /// 获取镜像历史
  Future<List<Map<String, dynamic>>> getImageHistory(
    SshSession session,
    String imageId,
  ) async {
    final items = await _engineRepository.requestJsonList(
      session,
      method: 'GET',
      path: '/images/${Uri.encodeComponent(imageId)}/history',
    );

    return items
        .whereType<Map>()
        .map(
          (item) =>
              _mapper.mapImageHistoryItem(Map<String, dynamic>.from(item)),
        )
        .toList();
  }

  /// 获取镜像创建容器时可预填的配置
  Future<Map<String, dynamic>> getImageCreateDefaults(
    SshSession session,
    String imageId,
  ) async {
    final detail = await _engineRepository.requestJsonObject(
      session,
      method: 'GET',
      path: '/images/${Uri.encodeComponent(imageId)}/json',
    );

    return _mapper.mapImageCreateDefaults(detail);
  }

  /// 获取引用镜像的容器
  Future<List<Map<String, dynamic>>> getImageContainers(
    SshSession session,
    String imageId,
  ) async {
    final filters = jsonEncode({
      'ancestor': [imageId],
    });
    final containers = await _engineRepository.requestJsonList(
      session,
      method: 'GET',
      path: '/containers/json',
      queryParameters: {'all': '1', 'filters': filters},
    );

    return containers.whereType<Map>().map((item) {
      final json = Map<String, dynamic>.from(item);
      final names =
          (json['Names'] as List?)
              ?.map((name) => name.toString())
              .where((name) => name.isNotEmpty)
              .toList() ??
          <String>[];
      return <String, dynamic>{
        'id': (json['Id'] ?? '').toString(),
        'name': names.isEmpty ? '' : _normalizeContainerName(names.first),
        'image': (json['Image'] ?? '').toString(),
        'state': (json['State'] ?? '').toString(),
        'status': (json['Status'] ?? '').toString(),
      };
    }).toList();
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

    final name = payload['name']?.toString().trim() ?? '';
    final requestBody = _mapper.buildCreateRequest(payload);
    final result = await _engineRepository.requestJsonObject(
      session,
      method: 'POST',
      path: '/containers/create',
      queryParameters: name.isEmpty ? null : {'name': name},
      body: requestBody,
    );
    final containerId = (result['Id'] ?? '').toString();

    final startAfterCreate = payload['start'] == true;
    if (startAfterCreate && containerId.isNotEmpty) {
      await startContainer(session, containerId);
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
    final name = _normalizeContainerName(nameRaw);
    final state =
        inspect['State'] as Map<String, dynamic>? ?? <String, dynamic>{};
    final wasRunning = state['Running'] == true;

    final payload = _buildCreatePayloadFromInspect(inspect);
    await removeContainer(session, containerId, force: true);
    final createResult = await createContainer(session, <String, dynamic>{
      ...payload,
      'start': false,
    });
    final newContainerId = (createResult['containerId'] ?? '').toString();

    if (wasRunning && newContainerId.isNotEmpty) {
      await startContainer(session, newContainerId);
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
    final filters = jsonEncode({
      'status': ['exited'],
    });
    final containers = await _engineRepository.requestJsonList(
      session,
      method: 'GET',
      path: '/containers/json',
      queryParameters: {'all': '1', 'filters': filters},
    );

    final ids = containers
        .whereType<Map>()
        .map((item) => (item['Id'] ?? '').toString())
        .where((id) => id.isNotEmpty)
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
    final filters = includeUnused
        ? jsonEncode(<String, List<String>>{})
        : jsonEncode({
            'dangling': ['true'],
          });
    return await _engineRepository.requestText(
      session,
      method: 'POST',
      path: '/images/prune',
      queryParameters: {'filters': filters},
    );
  }

  /// 检查 Docker 是否可用
  Future<bool> isDockerAvailable(SshSession session) async {
    return _engineRepository.ping(session);
  }

  /// 检查 Docker Compose 是否可用
  Future<bool> isComposeAvailable(SshSession session) async {
    try {
      final output = await _runComposeCommand(session, ['version']);
      return output.trim().isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// 获取 Compose 项目列表
  Future<List<Map<String, dynamic>>> listComposeProjects(
    SshSession session,
  ) async {
    late final List<Map<String, dynamic>> items;
    try {
      final output = await _runComposeCommand(session, [
        'compose',
        'ls',
        '--all',
        '--format',
        'json',
      ]);

      items = _decodeComposeJsonItems(output);
    } catch (e) {
      return <Map<String, dynamic>>[];
    }

    return items
        .map((item) {
          final name = _firstString(item, ['Name', 'name']);
          final status = _firstString(item, ['Status', 'status']);
          final configFiles = _firstString(item, [
            'ConfigFiles',
            'configFiles',
            'ConfigFilesText',
          ]);
          final workingDir = _firstString(item, [
            'WorkingDir',
            'workingDir',
            'Workdir',
          ]);

          return <String, dynamic>{
            'name': name,
            'status': status,
            'configFiles': configFiles,
            'workingDir': workingDir,
          };
        })
        .where((item) => item['name'].toString().isNotEmpty)
        .toList();
  }

  /// 创建 Compose 项目文件，并按需启动
  Future<Map<String, dynamic>> createComposeProject(
    SshSession session,
    Map<String, dynamic> payload,
  ) async {
    final projectName = payload['projectName']?.toString().trim() ?? '';
    final workingDir = payload['workingDir']?.toString().trim() ?? '';
    final fileName = payload['fileName']?.toString().trim().isNotEmpty == true
        ? payload['fileName'].toString().trim()
        : 'docker-compose.yml';
    final content = payload['content']?.toString() ?? '';
    final startAfterCreate = payload['startAfterCreate'] == true;

    if (projectName.isEmpty) {
      throw ArgumentError('projectName is required');
    }
    if (workingDir.isEmpty) {
      throw ArgumentError('workingDir is required');
    }
    if (content.trim().isEmpty) {
      throw ArgumentError('content is required');
    }
    if (!_isSafeComposeFileName(fileName)) {
      throw ArgumentError('fileName must be a .yml or .yaml file name');
    }

    await _runShellCommand(session, ['mkdir', '-p', workingDir]);
    final composePath = _joinPath(workingDir, fileName);
    await _sshRepository.writeFileStream(
      session,
      composePath,
      Stream.value(Uint8List.fromList(utf8.encode(content))),
    );

    var output = '';
    String? startError;
    if (startAfterCreate) {
      try {
        output = await upComposeProject(
          session,
          projectName: projectName,
          configFiles: [composePath],
          workingDir: workingDir,
        );
      } catch (e) {
        startError = e.toString();
      }
    }

    return {
      'projectName': projectName,
      'workingDir': workingDir,
      'configFiles': [composePath],
      'started': startAfterCreate && startError == null,
      'startError': startError,
      'output': output,
    };
  }

  /// 获取 Compose 项目服务状态
  Future<List<Map<String, dynamic>>> listComposeServices(
    SshSession session, {
    required String projectName,
    required List<String> configFiles,
    String? workingDir,
  }) async {
    late final List<Map<String, dynamic>> items;
    try {
      final output = await _runComposeProjectCommand(
        session,
        projectName: projectName,
        configFiles: configFiles,
        workingDir: workingDir,
        args: ['ps', '--format', 'json'],
      );
      items = _decodeComposeJsonItems(output);
    } catch (_) {
      final output = await _runComposeProjectCommand(
        session,
        projectName: projectName,
        configFiles: configFiles,
        workingDir: workingDir,
        args: ['ps'],
      );
      items = _parseComposeServicesTable(output);
    }

    return items.map((item) {
      return <String, dynamic>{
        'id': _firstString(item, ['ID', 'Id', 'id']),
        'name': _firstString(item, ['Name', 'name']),
        'service': _firstString(item, ['Service', 'service']),
        'project': _firstString(item, ['Project', 'project']),
        'image': _firstString(item, ['Image', 'image']),
        'state': _firstString(item, ['State', 'state']),
        'status': _firstString(item, ['Status', 'status']),
        'ports': _firstString(item, ['Publishers', 'Ports', 'ports']),
      };
    }).toList();
  }

  Future<String> upComposeProject(
    SshSession session, {
    required String projectName,
    required List<String> configFiles,
    String? workingDir,
  }) {
    return _runComposeProjectCommand(
      session,
      projectName: projectName,
      configFiles: configFiles,
      workingDir: workingDir,
      args: ['up', '-d'],
    );
  }

  Future<String> stopComposeProject(
    SshSession session, {
    required String projectName,
    required List<String> configFiles,
    String? workingDir,
  }) {
    return _runComposeProjectCommand(
      session,
      projectName: projectName,
      configFiles: configFiles,
      workingDir: workingDir,
      args: ['stop'],
    );
  }

  Future<String> restartComposeProject(
    SshSession session, {
    required String projectName,
    required List<String> configFiles,
    String? workingDir,
  }) {
    return _runComposeProjectCommand(
      session,
      projectName: projectName,
      configFiles: configFiles,
      workingDir: workingDir,
      args: ['restart'],
    );
  }

  Future<String> downComposeProject(
    SshSession session, {
    required String projectName,
    required List<String> configFiles,
    String? workingDir,
  }) {
    return _runComposeProjectCommand(
      session,
      projectName: projectName,
      configFiles: configFiles,
      workingDir: workingDir,
      args: ['down'],
    );
  }

  Future<String> getComposeLogs(
    SshSession session, {
    required String projectName,
    required List<String> configFiles,
    String? workingDir,
    int tail = 200,
  }) {
    return _runComposeProjectCommand(
      session,
      projectName: projectName,
      configFiles: configFiles,
      workingDir: workingDir,
      args: ['logs', '--no-color', '--tail', tail.toString()],
    );
  }

  /// 获取容器 inspect 详情
  Future<Map<String, dynamic>> inspectContainer(
    SshSession session,
    String containerId,
  ) async {
    return await _engineRepository.requestJsonObject(
      session,
      method: 'GET',
      path: '/containers/$containerId/json',
    );
  }

  /// 获取容器资源信息（docker stats --no-stream）
  Future<Map<String, dynamic>> getContainerStats(
    SshSession session,
    String containerId,
  ) async {
    final json = await _engineRepository.requestJsonObject(
      session,
      method: 'GET',
      path: '/containers/$containerId/stats',
      queryParameters: {'stream': 'false'},
    );
    return _mapper.mapContainerStats(json);
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

  List<String> _normalizeIds(List<String> ids) {
    return ids
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
  }

  List<String> _normalizeComposeFiles(List<String> files) {
    return files
        .map((file) => file.trim())
        .where((file) => file.isNotEmpty)
        .toSet()
        .toList();
  }

  bool _isSafeComposeFileName(String fileName) {
    if (fileName.contains('/') || fileName.contains('\\')) {
      return false;
    }

    final lower = fileName.toLowerCase();
    return lower.endsWith('.yml') || lower.endsWith('.yaml');
  }

  String _joinPath(String directory, String fileName) {
    final normalizedDirectory = directory.endsWith('/')
        ? directory.substring(0, directory.length - 1)
        : directory;
    return '$normalizedDirectory/$fileName';
  }

  Future<String> _runComposeProjectCommand(
    SshSession session, {
    required String projectName,
    required List<String> configFiles,
    String? workingDir,
    required List<String> args,
  }) {
    final files = _normalizeComposeFiles(configFiles);
    if (files.isEmpty) {
      throw ArgumentError('configFiles is required');
    }

    final commandArgs = <String>['compose'];
    final normalizedProjectName = projectName.trim();
    if (normalizedProjectName.isNotEmpty) {
      commandArgs.addAll(['-p', normalizedProjectName]);
    }
    for (final file in files) {
      commandArgs.addAll(['-f', file]);
    }
    commandArgs.addAll(args);

    return _runComposeCommand(session, commandArgs, workingDir: workingDir);
  }

  Future<String> _runComposeCommand(
    SshSession session,
    List<String> args, {
    String? workingDir,
  }) async {
    try {
      return await _runShellCommand(session, [
        'docker',
        ...args,
      ], workingDir: workingDir);
    } catch (error) {
      if (args.isEmpty || args.first != 'compose') {
        rethrow;
      }

      try {
        return await _runShellCommand(session, [
          'docker-compose',
          ...args.skip(1),
        ], workingDir: workingDir);
      } catch (_) {
        throw error;
      }
    }
  }

  Future<String> _runShellCommand(
    SshSession session,
    List<String> args, {
    String? workingDir,
  }) async {
    const statusMarker = '__SSH_TOOL_COMPOSE_STATUS__';
    final dockerCommand = args.map(_shellQuote).join(' ');
    final directory = workingDir?.trim();
    final command = [
      if (directory != null && directory.isNotEmpty)
        'cd ${_shellQuote(directory)}',
      dockerCommand,
    ].join(' && ');
    final wrappedCommand =
        'sh -lc ${_shellQuote('$command; code=\$?; printf "\\n$statusMarker:%s" "\$code"; exit 0')}';
    final output = await _sshRepository.exec(session, wrappedCommand);
    final markerIndex = output.lastIndexOf('\n$statusMarker:');
    if (markerIndex < 0) {
      throw Exception(
        output.trim().isEmpty ? 'Compose command failed' : output.trim(),
      );
    }

    final body = output.substring(0, markerIndex);
    final statusText = output
        .substring(markerIndex + statusMarker.length + 2)
        .trim();
    final statusCode = int.tryParse(statusText);
    if (statusCode == null || statusCode != 0) {
      throw Exception(
        body.trim().isEmpty ? 'Compose command failed' : body.trim(),
      );
    }

    return body.trim();
  }

  List<Map<String, dynamic>> _parseComposeProjectsTable(String output) {
    return output
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .where((line) => !line.toLowerCase().startsWith('name'))
        .map((line) {
          final parts = line.split(RegExp(r'\s{2,}'));
          if (parts.isEmpty) {
            return <String, dynamic>{};
          }

          return <String, dynamic>{
            'Name': parts[0],
            'Status': parts.length > 1 ? parts[1] : '',
            'ConfigFiles': parts.length > 2 ? parts.sublist(2).join(', ') : '',
            'WorkingDir': '',
          };
        })
        .where((item) => item['Name']?.toString().isNotEmpty == true)
        .toList();
  }

  List<Map<String, dynamic>> _parseComposeServicesTable(String output) {
    return output
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .where((line) => !line.toLowerCase().startsWith('name'))
        .map((line) {
          final parts = line.split(RegExp(r'\s{2,}'));
          if (parts.isEmpty) {
            return <String, dynamic>{};
          }

          return <String, dynamic>{
            'Name': parts[0],
            'Service': parts[0],
            'Image': parts.length > 1 ? parts[1] : '',
            'State': parts.length > 2 ? parts[2] : '',
            'Status': parts.length > 2 ? parts.sublist(2).join(' ') : '',
            'Ports': parts.length > 3 ? parts.sublist(3).join(', ') : '',
          };
        })
        .where((item) => item['Name']?.toString().isNotEmpty == true)
        .toList();
  }

  List<Map<String, dynamic>> _decodeComposeJsonItems(String output) {
    final trimmed = output.trim();
    if (trimmed.isEmpty) {
      return <Map<String, dynamic>>[];
    }

    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
      }
      if (decoded is Map) {
        return [Map<String, dynamic>.from(decoded)];
      }
    } catch (_) {
      // Some compose versions output one JSON object per line.
    }

    return trimmed
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .map((line) => jsonDecode(line))
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  String _firstString(Map<String, dynamic> item, List<String> keys) {
    for (final key in keys) {
      final value = item[key];
      if (value == null) {
        continue;
      }
      if (value is List) {
        return value.map((entry) => entry.toString()).join(', ');
      }
      return value.toString();
    }

    return '';
  }

  String _shellQuote(String value) {
    return "'${value.replaceAll("'", "'\\''")}'";
  }

  Future<Set<String>> _getUsedImageIds(SshSession session) async {
    try {
      final containers = await _engineRepository.requestJsonList(
        session,
        method: 'GET',
        path: '/containers/json',
        queryParameters: {'all': '1'},
      );

      return containers
          .whereType<Map>()
          .map((item) => (item['ImageID'] ?? item['ImageId'] ?? '').toString())
          .where((id) => id.isNotEmpty)
          .toSet();
    } catch (_) {
      return <String>{};
    }
  }

  int _toInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _decodeDockerLogs(Uint8List bytes) {
    if (bytes.isEmpty) {
      return '';
    }

    if (!_looksLikeDockerMultiplexedStream(bytes)) {
      return utf8.decode(bytes, allowMalformed: true);
    }

    final output = BytesBuilder(copy: false);
    var offset = 0;
    while (offset + 8 <= bytes.length) {
      final frameLength =
          (bytes[offset + 4] << 24) |
          (bytes[offset + 5] << 16) |
          (bytes[offset + 6] << 8) |
          bytes[offset + 7];
      final frameStart = offset + 8;
      final frameEnd = frameStart + frameLength;
      if (frameLength < 0 || frameEnd > bytes.length) {
        return utf8.decode(bytes, allowMalformed: true);
      }

      final streamType = bytes[offset];
      if (streamType == 1 || streamType == 2) {
        output.add(Uint8List.sublistView(bytes, frameStart, frameEnd));
      }
      offset = frameEnd;
    }

    if (offset != bytes.length) {
      return utf8.decode(bytes, allowMalformed: true);
    }

    return utf8.decode(output.takeBytes(), allowMalformed: true);
  }

  bool _looksLikeDockerMultiplexedStream(Uint8List bytes) {
    if (bytes.length < 8) {
      return false;
    }

    final streamType = bytes[0];
    if (streamType != 0 && streamType != 1 && streamType != 2) {
      return false;
    }

    return bytes[1] == 0 && bytes[2] == 0 && bytes[3] == 0;
  }

  String _normalizeContainerName(String value) {
    if (value.startsWith('/')) {
      return value.substring(1);
    }
    return value;
  }

  Map<String, dynamic> _buildCreatePayloadFromInspect(
    Map<String, dynamic> inspect,
  ) {
    final config =
        inspect['Config'] as Map<String, dynamic>? ?? <String, dynamic>{};
    final hostConfig =
        inspect['HostConfig'] as Map<String, dynamic>? ?? <String, dynamic>{};
    final nameRaw = inspect['Name']?.toString() ?? '';
    final name = _normalizeContainerName(nameRaw);

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
            if (hostPort.isEmpty) {
              continue;
            }
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
          if (source.isEmpty || destination.isEmpty) {
            continue;
          }
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

  _ImageReference _splitImageReference(String imageRef) {
    final value = imageRef.trim();
    final digestIndex = value.indexOf('@');
    if (digestIndex >= 0) {
      return _ImageReference(value, '');
    }

    final lastSlash = value.lastIndexOf('/');
    final lastColon = value.lastIndexOf(':');
    if (lastColon > lastSlash) {
      return _ImageReference(
        value.substring(0, lastColon),
        value.substring(lastColon + 1),
      );
    }

    return _ImageReference(value, 'latest');
  }
}

class _ImageReference {
  final String repository;
  final String tag;

  const _ImageReference(this.repository, this.tag);
}
