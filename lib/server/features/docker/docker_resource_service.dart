import 'package:logging/logging.dart';

import 'package:host_deck/server/core/ssh/ssh_session.dart';
import 'package:host_deck/server/features/docker/docker_engine_mapper.dart';
import 'package:host_deck/server/features/docker/docker_engine_repository.dart';
import 'package:host_deck/server/features/docker/docker_network.dart';
import 'package:host_deck/server/features/docker/docker_volume.dart';

class DockerResourceService {
  static const _builtInNetworkNames = {'bridge', 'host', 'none'};

  final DockerEngineRepository _engineRepository;
  final DockerEngineMapper _mapper;
  final _log = Logger('DockerResourceService');

  DockerResourceService(this._engineRepository, this._mapper);

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

  Future<void> removeNetwork(SshSession session, String networkId) async {
    final network = await inspectNetwork(session, networkId);
    final networkName = (network['Name'] ?? '').toString().trim().toLowerCase();
    if (_builtInNetworkNames.contains(networkName)) {
      throw StateError('Docker 初始网络不可删除。');
    }

    await _engineRepository.request(
      session,
      method: 'DELETE',
      path: '/networks/${Uri.encodeComponent(networkId)}',
    );
  }

  Future<void> removeVolume(SshSession session, String volumeName) async {
    await _engineRepository.request(
      session,
      method: 'DELETE',
      path: '/volumes/${Uri.encodeComponent(volumeName)}',
    );
  }

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

  Future<Map<String, dynamic>> pruneBuildCache(
    SshSession session, {
    bool includeAll = false,
  }) async {
    final result = await _engineRepository.requestJsonObject(
      session,
      method: 'POST',
      path: '/build/prune',
      queryParameters: {'all': includeAll ? '1' : '0'},
    );
    final deleted =
        (result['CachesDeleted'] as List?)
            ?.map((item) => item.toString())
            .where((item) => item.isNotEmpty)
            .toList() ??
        <String>[];

    return {
      'deleted': deleted,
      'deletedCount': deleted.length,
      'spaceReclaimed': _readInt(result, 'SpaceReclaimed'),
    };
  }

  int _readInt(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
