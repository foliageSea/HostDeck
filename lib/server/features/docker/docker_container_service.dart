import 'dart:convert';
import 'dart:typed_data';

import 'package:logging/logging.dart';

import 'package:host_deck/server/core/ssh/ssh_session.dart';
import 'package:host_deck/server/features/docker/docker_container.dart';
import 'package:host_deck/server/features/docker/docker_engine_mapper.dart';
import 'package:host_deck/server/features/docker/docker_engine_repository.dart';

class DockerContainerService {
  final DockerEngineRepository _engineRepository;
  final DockerEngineMapper _mapper;
  final _log = Logger('DockerContainerService');

  DockerContainerService(this._engineRepository, this._mapper);

  String debugDecodeDockerLogs(Uint8List bytes) {
    return _decodeDockerLogs(bytes);
  }

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

  Future<bool> isDockerAvailable(SshSession session) async {
    return _engineRepository.ping(session);
  }

  Future<void> startContainer(SshSession session, String containerId) async {
    await _engineRepository.request(
      session,
      method: 'POST',
      path: '/containers/$containerId/start',
    );
  }

  Future<void> stopContainer(SshSession session, String containerId) async {
    await _engineRepository.request(
      session,
      method: 'POST',
      path: '/containers/$containerId/stop',
    );
  }

  Future<void> restartContainer(SshSession session, String containerId) async {
    await _engineRepository.request(
      session,
      method: 'POST',
      path: '/containers/$containerId/restart',
    );
  }

  Future<void> pauseContainer(SshSession session, String containerId) async {
    await _engineRepository.request(
      session,
      method: 'POST',
      path: '/containers/$containerId/pause',
    );
  }

  Future<void> unpauseContainer(SshSession session, String containerId) async {
    await _engineRepository.request(
      session,
      method: 'POST',
      path: '/containers/$containerId/unpause',
    );
  }

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

  List<String> _normalizeIds(List<String> ids) {
    return ids
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
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
}
