import 'package:host_deck/server/features/docker/docker_container.dart';
import 'package:host_deck/server/features/docker/docker_image.dart';
import 'package:host_deck/server/features/docker/docker_network.dart';
import 'package:host_deck/server/features/docker/docker_volume.dart';

class DockerEngineMapper {
  DockerContainer mapContainerSummary(Map<String, dynamic> json) {
    final names =
        (json['Names'] as List?)
            ?.map((item) => item.toString())
            .where((item) => item.isNotEmpty)
            .toList() ??
        <String>[];
    final ports =
        (json['Ports'] as List?)
            ?.whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList() ??
        <Map<String, dynamic>>[];
    final networkSettings = _asMap(json['NetworkSettings']);
    final networks = _asMap(networkSettings['Networks']);

    return DockerContainer(
      id: (json['Id'] ?? '').toString(),
      name: _normalizeContainerName(names.isNotEmpty ? names.first : ''),
      image: (json['Image'] ?? '').toString(),
      status: (json['Status'] ?? '').toString(),
      state: (json['State'] ?? '').toString(),
      ports: _formatContainerPorts(ports),
      networks: _mapContainerNetworks(networks),
      createdAt: _parseUnixTimestamp(json['Created']),
    );
  }

  List<DockerContainerNetwork> _mapContainerNetworks(
    Map<String, dynamic> networks,
  ) {
    final result = <DockerContainerNetwork>[];

    networks.forEach((key, value) {
      final network = _asMap(value);
      final name = key.toString().trim();
      final ipAddress = (network['IPAddress'] ?? '').toString().trim();
      if (name.isEmpty) {
        return;
      }

      result.add(DockerContainerNetwork(name: name, ipAddress: ipAddress));
    });

    result.sort((a, b) => a.name.compareTo(b.name));
    return result;
  }

  List<DockerImage> mapImageSummaries(
    List<dynamic> images,
    Set<String> usedImageIds,
  ) {
    final result = <DockerImage>[];

    for (final item in images) {
      if (item is! Map) {
        continue;
      }

      final json = Map<String, dynamic>.from(item);
      final id = (json['Id'] ?? '').toString();
      final createdAt = _parseUnixTimestamp(json['Created']);
      final size = _formatBytes(_toInt(json['Size']));
      final tags =
          (json['RepoTags'] as List?)
              ?.map((tag) => tag.toString())
              .where((tag) => tag.isNotEmpty)
              .toList() ??
          <String>[];

      if (tags.isEmpty) {
        result.add(
          DockerImage(
            id: id,
            repository: '<none>',
            tag: '<none>',
            size: size,
            createdAt: createdAt,
            dangling: true,
            inUse: _isImageInUse(id, usedImageIds),
          ),
        );
        continue;
      }

      for (final rawTag in tags) {
        final parsed = _splitRepositoryAndTag(rawTag);
        final dangling =
            parsed.repository == '<none>' && parsed.tag == '<none>';
        result.add(
          DockerImage(
            id: id,
            repository: parsed.repository,
            tag: parsed.tag,
            size: size,
            createdAt: createdAt,
            dangling: dangling,
            inUse: _isImageInUse(id, usedImageIds),
          ),
        );
      }
    }

    return result;
  }

  Map<String, dynamic> mapImageHistoryItem(Map<String, dynamic> json) {
    final createdAt = _parseUnixTimestamp(json['Created']);

    return {
      'id': (json['Id'] ?? '').toString(),
      'createdSince': createdAt == null ? '' : _formatRelativeTime(createdAt),
      'createdAt': createdAt?.toIso8601String() ?? '',
      'createdBy': (json['CreatedBy'] ?? '').toString(),
      'size': _formatBytes(_toInt(json['Size'])),
      'comment': (json['Comment'] ?? '').toString(),
    };
  }

  Map<String, dynamic> mapImageCreateDefaults(Map<String, dynamic> json) {
    final config = _asMap(json['Config']);
    final exposedPorts = _asMap(config['ExposedPorts']);
    final volumes = _asMap(config['Volumes']);

    final ports =
        exposedPorts.keys
            .map(_formatImagePortMapping)
            .where((port) => port.isNotEmpty)
            .toList()
          ..sort();
    final volumePaths =
        volumes.keys
            .map((volume) => volume.toString().trim())
            .where((volume) => volume.isNotEmpty)
            .toList()
          ..sort();

    return {'ports': ports, 'volumes': volumePaths};
  }

  Map<String, dynamic> mapContainerStats(Map<String, dynamic> json) {
    final cpuStats = _asMap(json['cpu_stats']);
    final preCpuStats = _asMap(json['precpu_stats']);
    final cpuUsage = _asMap(cpuStats['cpu_usage']);
    final preCpuUsage = _asMap(preCpuStats['cpu_usage']);
    final totalUsage = _toDouble(cpuUsage['total_usage']);
    final preTotalUsage = _toDouble(preCpuUsage['total_usage']);
    final systemUsage = _toDouble(cpuStats['system_cpu_usage']);
    final preSystemUsage = _toDouble(preCpuStats['system_cpu_usage']);
    final cpuDelta = totalUsage - preTotalUsage;
    final systemDelta = systemUsage - preSystemUsage;
    final onlineCpus = _resolveOnlineCpuCount(cpuStats, cpuUsage);
    final cpuPercent = cpuDelta > 0 && systemDelta > 0
        ? (cpuDelta / systemDelta) * onlineCpus * 100
        : 0.0;

    final memoryStats = _asMap(json['memory_stats']);
    final memoryUsage = _toDouble(memoryStats['usage']);
    final memoryLimit = _toDouble(memoryStats['limit']);
    final memoryCache = _extractMemoryCache(_asMap(memoryStats['stats']));
    final workingSet = (memoryUsage - memoryCache).clamp(0, double.infinity);
    final memoryPercent = memoryLimit > 0
        ? (workingSet / memoryLimit) * 100
        : 0.0;

    final networks = _asMap(json['networks']);
    var rxBytes = 0.0;
    var txBytes = 0.0;
    networks.forEach((_, value) {
      final network = _asMap(value);
      rxBytes += _toDouble(network['rx_bytes']);
      txBytes += _toDouble(network['tx_bytes']);
    });

    final blockIo = _asMap(json['blkio_stats']);
    final ioItems =
        (blockIo['io_service_bytes_recursive'] as List?)
            ?.whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList() ??
        <Map<String, dynamic>>[];
    var readBytes = 0.0;
    var writeBytes = 0.0;
    for (final item in ioItems) {
      final op = (item['op'] ?? '').toString().toLowerCase();
      final value = _toDouble(item['value']);
      if (op == 'read') {
        readBytes += value;
      } else if (op == 'write') {
        writeBytes += value;
      }
    }

    final pidsStats = _asMap(json['pids_stats']);
    final name = _normalizeContainerName((json['name'] ?? '').toString());

    return {
      'id': (json['id'] ?? '').toString(),
      'name': name,
      'cpuPercent': _formatPercent(cpuPercent),
      'memPercent': _formatPercent(memoryPercent),
      'memUsage': '${_formatBytes(workingSet)} / ${_formatBytes(memoryLimit)}',
      'netIO': '${_formatBytes(rxBytes)} / ${_formatBytes(txBytes)}',
      'blockIO': '${_formatBytes(readBytes)} / ${_formatBytes(writeBytes)}',
      'pids': _toInt(pidsStats['current']).toString(),
    };
  }

  List<DockerNetwork> mapNetworkSummaries(List<dynamic> networks) {
    return networks
        .whereType<Map>()
        .map((item) => mapNetworkSummary(Map<String, dynamic>.from(item)))
        .where((item) => item.name.isNotEmpty)
        .toList();
  }

  DockerNetwork mapNetworkSummary(Map<String, dynamic> json) {
    final containers = _asMap(json['Containers']);
    final ipamConfigs = (json['IPAM'] as Map?)?['Config'] as List? ?? const [];
    final firstIpv4Config = ipamConfigs.whereType<Map>().map(_asMap).firstWhere(
      (config) {
        final subnet = (config['Subnet'] ?? '').toString();
        return subnet.isNotEmpty && !subnet.contains(':');
      },
      orElse: () => const <String, dynamic>{},
    );
    final connectedContainerNames =
        containers.values
            .map((value) => _asMap(value)['Name']?.toString().trim() ?? '')
            .where((name) => name.isNotEmpty)
            .toSet()
            .toList()
          ..sort();

    return DockerNetwork(
      id: (json['Id'] ?? '').toString(),
      name: (json['Name'] ?? '').toString(),
      driver: (json['Driver'] ?? '').toString(),
      scope: (json['Scope'] ?? '').toString(),
      createdAt: _parseDateTime(json['Created']),
      internal: json['Internal'] == true,
      attachable: json['Attachable'] == true,
      ingress: json['Ingress'] == true,
      subnet: (firstIpv4Config['Subnet'] ?? '').toString(),
      gateway: (firstIpv4Config['Gateway'] ?? '').toString(),
      connectedContainers: containers.length,
      connectedContainerNames: connectedContainerNames,
    );
  }

  List<DockerVolume> mapVolumeSummaries(List<dynamic> volumes) {
    return volumes
        .whereType<Map>()
        .map((item) => mapVolumeSummary(Map<String, dynamic>.from(item)))
        .where((item) => item.name.isNotEmpty)
        .toList();
  }

  DockerVolume mapVolumeSummary(Map<String, dynamic> json) {
    final usageData = _asMap(json['UsageData']);

    return DockerVolume(
      name: (json['Name'] ?? '').toString(),
      driver: (json['Driver'] ?? '').toString(),
      scope: (json['Scope'] ?? '').toString(),
      mountpoint: (json['Mountpoint'] ?? '').toString(),
      createdAt: _parseDateTime(json['CreatedAt']),
      refCount: _toInt(usageData['RefCount']),
    );
  }

  Map<String, dynamic> buildCreateNetworkRequest(Map<String, dynamic> payload) {
    final name = payload['name']?.toString().trim() ?? '';
    if (name.isEmpty) {
      throw Exception('name is required');
    }

    final driver = payload['driver']?.toString().trim() ?? 'bridge';
    return {
      'Name': name,
      'Driver': driver.isEmpty ? 'bridge' : driver,
      'CheckDuplicate': true,
      if (payload['internal'] == true) 'Internal': true,
      if (payload['attachable'] == true) 'Attachable': true,
      if (payload['ingress'] == true) 'Ingress': true,
      if (_toStringMap(payload['options']).isNotEmpty)
        'Options': _toStringMap(payload['options']),
      if (_toStringMap(payload['labels']).isNotEmpty)
        'Labels': _toStringMap(payload['labels']),
    };
  }

  Map<String, dynamic> buildCreateVolumeRequest(Map<String, dynamic> payload) {
    final name = payload['name']?.toString().trim() ?? '';
    if (name.isEmpty) {
      throw Exception('name is required');
    }

    final driver = payload['driver']?.toString().trim() ?? 'local';
    return {
      'Name': name,
      'Driver': driver.isEmpty ? 'local' : driver,
      if (_toStringMap(payload['options']).isNotEmpty)
        'DriverOpts': _toStringMap(payload['options']),
      if (_toStringMap(payload['labels']).isNotEmpty)
        'Labels': _toStringMap(payload['labels']),
    };
  }

  Map<String, dynamic> buildCreateRequest(Map<String, dynamic> payload) {
    final image = payload['image']?.toString().trim() ?? '';
    if (image.isEmpty) {
      throw Exception('image is required');
    }

    final request = <String, dynamic>{'Image': image};
    final hostConfig = <String, dynamic>{};

    final ports = payload['ports'];
    final exposedPorts = <String, dynamic>{};
    final portBindings = <String, List<Map<String, String>>>{};
    if (ports is List) {
      for (final item in ports) {
        final mapping = _parsePortMapping(item.toString().trim());
        if (mapping == null) {
          continue;
        }

        exposedPorts[mapping.containerPort] = <String, dynamic>{};
        if (mapping.hostBinding != null) {
          portBindings
              .putIfAbsent(mapping.containerPort, () => <Map<String, String>>[])
              .add(mapping.hostBinding!);
        }
      }
    }

    if (exposedPorts.isNotEmpty) {
      request['ExposedPorts'] = exposedPorts;
    }
    if (portBindings.isNotEmpty) {
      hostConfig['PortBindings'] = portBindings;
    }

    final env = _toStringList(payload['env']);
    if (env.isNotEmpty) {
      request['Env'] = env;
    }

    final volumes = _toStringList(payload['volumes']);
    final binds = <String>[];
    final anonymousVolumes = <String, dynamic>{};
    for (final volume in volumes) {
      if (volume.contains(':')) {
        binds.add(volume);
      } else {
        anonymousVolumes[volume] = <String, dynamic>{};
      }
    }
    if (binds.isNotEmpty) {
      hostConfig['Binds'] = binds;
    }
    if (anonymousVolumes.isNotEmpty) {
      request['Volumes'] = anonymousVolumes;
    }

    final restartPolicy = payload['restartPolicy']?.toString().trim() ?? '';
    if (restartPolicy.isNotEmpty && restartPolicy != 'no') {
      hostConfig['RestartPolicy'] = {'Name': restartPolicy};
    }

    final entrypoint = _toStringList(payload['entrypoint']);
    if (entrypoint.isNotEmpty) {
      request['Entrypoint'] = entrypoint;
    }

    final cmd = _toStringList(payload['cmd']);
    if (cmd.isNotEmpty) {
      request['Cmd'] = cmd;
    }

    if (hostConfig.isNotEmpty) {
      request['HostConfig'] = hostConfig;
    }

    return request;
  }

  bool isImageInUse(String imageId, Set<String> usedImageIds) {
    return _isImageInUse(imageId, usedImageIds);
  }

  List<String> _toStringList(dynamic value) {
    if (value is! List) {
      return <String>[];
    }

    return value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  Map<String, String> _toStringMap(dynamic value) {
    if (value is! Map) {
      return <String, String>{};
    }

    final result = <String, String>{};
    value.forEach((key, item) {
      final normalizedKey = key.toString().trim();
      final normalizedValue = item?.toString().trim() ?? '';
      if (normalizedKey.isEmpty || normalizedValue.isEmpty) {
        return;
      }

      result[normalizedKey] = normalizedValue;
    });
    return result;
  }

  _RepositoryTag _splitRepositoryAndTag(String raw) {
    final lastSlash = raw.lastIndexOf('/');
    final lastColon = raw.lastIndexOf(':');
    if (lastColon > lastSlash) {
      return _RepositoryTag(
        repository: raw.substring(0, lastColon),
        tag: raw.substring(lastColon + 1),
      );
    }

    return _RepositoryTag(repository: raw, tag: '<none>');
  }

  DateTime? _parseUnixTimestamp(dynamic value) {
    final timestamp = int.tryParse(value?.toString() ?? '');
    if (timestamp == null || timestamp <= 0) {
      return null;
    }

    return DateTime.fromMillisecondsSinceEpoch(timestamp * 1000, isUtc: true);
  }

  DateTime? _parseDateTime(dynamic value) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) {
      return null;
    }

    return DateTime.tryParse(text);
  }

  List<String> _formatContainerPorts(List<Map<String, dynamic>> ports) {
    final result = <String>[];
    for (final port in ports) {
      final privatePort = (port['PrivatePort'] ?? '').toString();
      final publicPort = (port['PublicPort'] ?? '').toString();
      final ip = (port['IP'] ?? '').toString();
      final type = (port['Type'] ?? 'tcp').toString();
      if (privatePort.isEmpty) {
        continue;
      }

      if (publicPort.isNotEmpty) {
        final host = ip.isNotEmpty ? '$ip:$publicPort' : publicPort;
        result.add('$host->$privatePort/$type');
      } else {
        result.add('$privatePort/$type');
      }
    }

    return result;
  }

  String _normalizeContainerName(String value) {
    if (value.startsWith('/')) {
      return value.substring(1);
    }
    return value;
  }

  bool _isImageInUse(String imageId, Set<String> usedImageIds) {
    if (imageId.isEmpty) {
      return false;
    }

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

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return <String, dynamic>{};
  }

  int _resolveOnlineCpuCount(
    Map<String, dynamic> cpuStats,
    Map<String, dynamic> cpuUsage,
  ) {
    final onlineCpus = _toInt(cpuStats['online_cpus']);
    if (onlineCpus > 0) {
      return onlineCpus;
    }

    final perCpuUsage = cpuUsage['percpu_usage'];
    if (perCpuUsage is List && perCpuUsage.isNotEmpty) {
      return perCpuUsage.length;
    }

    return 1;
  }

  double _extractMemoryCache(Map<String, dynamic> stats) {
    if (stats['cache'] != null) {
      return _toDouble(stats['cache']);
    }
    if (stats['inactive_file'] != null) {
      return _toDouble(stats['inactive_file']);
    }
    if (stats['total_inactive_file'] != null) {
      return _toDouble(stats['total_inactive_file']);
    }
    return 0.0;
  }

  String _formatPercent(double value) {
    return '${value.toStringAsFixed(1)}%';
  }

  String _formatBytes(num bytes) {
    if (bytes <= 0) {
      return '0 B';
    }

    const units = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];
    var size = bytes.toDouble();
    var unitIndex = 0;

    while (size >= 1024 && unitIndex < units.length - 1) {
      size /= 1024;
      unitIndex += 1;
    }

    final digits = unitIndex == 0 || size >= 10 ? 0 : 1;
    return '${size.toStringAsFixed(digits)} ${units[unitIndex]}';
  }

  String _formatImagePortMapping(String value) {
    final raw = value.trim();
    if (raw.isEmpty) {
      return '';
    }

    final segments = raw.split('/');
    final containerPort = segments.first.trim();
    final protocol = segments.length > 1 && segments.last.trim().isNotEmpty
        ? segments.last.trim()
        : 'tcp';
    if (containerPort.isEmpty) {
      return '';
    }

    return '$containerPort:$containerPort/$protocol';
  }

  String _formatRelativeTime(DateTime value) {
    final duration = DateTime.now().toUtc().difference(value.toUtc());
    if (duration.inSeconds < 60) {
      return '${duration.inSeconds} seconds ago';
    }
    if (duration.inMinutes < 60) {
      return '${duration.inMinutes} minutes ago';
    }
    if (duration.inHours < 24) {
      return '${duration.inHours} hours ago';
    }
    if (duration.inDays < 30) {
      return '${duration.inDays} days ago';
    }

    final months = (duration.inDays / 30).floor();
    if (months < 12) {
      return '$months months ago';
    }

    final years = (duration.inDays / 365).floor();
    return '$years years ago';
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

  double _toDouble(dynamic value) {
    if (value is double) {
      return value;
    }
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  _PortMapping? _parsePortMapping(String value) {
    if (value.isEmpty) {
      return null;
    }

    final segments = value.split('/');
    final protocol = segments.length > 1 && segments.last.trim().isNotEmpty
        ? segments.last.trim()
        : 'tcp';
    final portSpec = segments.first.trim();
    if (portSpec.isEmpty) {
      return null;
    }

    final parts = portSpec.split(':');
    String containerPort;
    String? hostPort;
    String? hostIp;

    if (parts.length == 1) {
      containerPort = parts[0];
    } else if (parts.length == 2) {
      hostPort = parts[0];
      containerPort = parts[1];
    } else {
      hostIp = parts[0];
      hostPort = parts[1];
      containerPort = parts.sublist(2).join(':');
    }

    containerPort = containerPort.trim();
    hostPort = hostPort?.trim();
    hostIp = hostIp?.trim();
    if (containerPort.isEmpty) {
      return null;
    }

    final containerPortKey = containerPort.contains('/')
        ? containerPort
        : '$containerPort/$protocol';
    Map<String, String>? hostBinding;
    if (hostPort != null && hostPort.isNotEmpty) {
      hostBinding = <String, String>{'HostPort': hostPort};
      if (hostIp != null && hostIp.isNotEmpty) {
        hostBinding['HostIp'] = hostIp;
      }
    }

    return _PortMapping(containerPortKey, hostBinding);
  }
}

class _RepositoryTag {
  final String repository;
  final String tag;

  const _RepositoryTag({required this.repository, required this.tag});
}

class _PortMapping {
  final String containerPort;
  final Map<String, String>? hostBinding;

  const _PortMapping(this.containerPort, this.hostBinding);
}
