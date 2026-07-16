import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:host_deck/server/core/ssh/ssh_operation_limiter.dart';
import 'package:host_deck/server/core/ssh/ssh_repository.dart';
import 'package:host_deck/server/core/ssh/ssh_session.dart';
import 'package:host_deck/server/features/docker/docker_engine_mapper.dart';
import 'package:host_deck/server/features/docker/docker_engine_repository.dart';
import 'package:host_deck/server/features/docker/docker_service.dart';

void main() {
  group('DockerEngineMapper', () {
    final mapper = DockerEngineMapper();

    test('maps image summaries into repo-tag rows', () {
      final images = mapper.mapImageSummaries(
        [
          {
            'Id': 'sha256:abc123',
            'Created': 1710000000,
            'Size': 52428800,
            'RepoTags': ['nginx:latest', 'nginx:stable'],
          },
          {
            'Id': 'sha256:def456',
            'Created': 1710000100,
            'Size': 1024,
            'RepoTags': null,
          },
        ],
        {'sha256:abc123'},
      );

      expect(images, hasLength(3));
      expect(images[0].repository, 'nginx');
      expect(images[0].tag, 'latest');
      expect(images[0].inUse, isTrue);
      expect(images[1].tag, 'stable');
      expect(images[2].repository, '<none>');
      expect(images[2].dangling, isTrue);
    });

    test('maps stats payload into formatted summary', () {
      final stats = mapper.mapContainerStats({
        'id': 'container-1',
        'name': '/web',
        'cpu_stats': {
          'system_cpu_usage': 2000000000,
          'online_cpus': 2,
          'cpu_usage': {
            'total_usage': 400000000,
            'percpu_usage': [200000000, 200000000],
          },
        },
        'precpu_stats': {
          'system_cpu_usage': 1000000000,
          'cpu_usage': {'total_usage': 200000000},
        },
        'memory_stats': {
          'usage': 268435456,
          'limit': 536870912,
          'stats': {'cache': 67108864},
        },
        'networks': {
          'eth0': {'rx_bytes': 1024, 'tx_bytes': 2048},
        },
        'blkio_stats': {
          'io_service_bytes_recursive': [
            {'op': 'Read', 'value': 4096},
            {'op': 'Write', 'value': 8192},
          ],
        },
        'pids_stats': {'current': 12},
      });

      expect(stats['id'], 'container-1');
      expect(stats['name'], 'web');
      expect(stats['cpuPercent'], '40.0%');
      expect(stats['memPercent'], '37.5%');
      expect(stats['memUsage'], '192 MB / 512 MB');
      expect(stats['netIO'], '1.0 KB / 2.0 KB');
      expect(stats['blockIO'], '4.0 KB / 8.0 KB');
      expect(stats['pids'], '12');
    });

    test('builds create request body from ui payload', () {
      final request = mapper.buildCreateRequest({
        'image': 'nginx:latest',
        'ports': ['127.0.0.1:8080:80', '443:443/tcp'],
        'env': ['NODE_ENV=production'],
        'volumes': ['/host/data:/data:ro', '/cache'],
        'restartPolicy': 'always',
        'entrypoint': ['/docker-entrypoint.sh'],
        'cmd': ['nginx', '-g', 'daemon off;'],
      });

      expect(request['Image'], 'nginx:latest');
      expect(request['Env'], ['NODE_ENV=production']);
      expect(request['Entrypoint'], ['/docker-entrypoint.sh']);
      expect(request['Cmd'], ['nginx', '-g', 'daemon off;']);
      expect(request['Volumes'], {'/cache': <String, dynamic>{}});
      expect(request['ExposedPorts'], {
        '80/tcp': <String, dynamic>{},
        '443/tcp': <String, dynamic>{},
      });
      expect(request['HostConfig'], {
        'PortBindings': {
          '80/tcp': [
            {'HostPort': '8080', 'HostIp': '127.0.0.1'},
          ],
          '443/tcp': [
            {'HostPort': '443'},
          ],
        },
        'Binds': ['/host/data:/data:ro'],
        'RestartPolicy': {'Name': 'always'},
      });
    });

    test('maps image create defaults from inspect payload', () {
      final defaults = mapper.mapImageCreateDefaults({
        'Config': {
          'ExposedPorts': {'80/tcp': {}, '443/tcp': {}, '53/udp': {}},
          'Volumes': {'/data': {}, '/var/lib/app': {}},
        },
      });

      expect(defaults['ports'], ['443:443/tcp', '53:53/udp', '80:80/tcp']);
      expect(defaults['volumes'], ['/data', '/var/lib/app']);
    });

    test('maps network summaries into ui rows', () {
      final networks = mapper.mapNetworkSummaries([
        {
          'Id': 'network-1',
          'Name': 'app-network',
          'Driver': 'bridge',
          'Scope': 'local',
          'Created': '2024-03-01T10:20:30.000000000Z',
          'Internal': true,
          'Attachable': false,
          'Ingress': false,
          'IPAM': {
            'Config': [
              {'Subnet': '172.18.0.0/16', 'Gateway': '172.18.0.1'},
            ],
          },
          'Containers': {
            'container-1': {'Name': 'web'},
            'container-2': {'Name': 'api'},
          },
        },
      ]);

      expect(networks, hasLength(1));
      expect(networks.first.name, 'app-network');
      expect(networks.first.driver, 'bridge');
      expect(networks.first.scope, 'local');
      expect(networks.first.internal, isTrue);
      expect(networks.first.subnet, '172.18.0.0/16');
      expect(networks.first.gateway, '172.18.0.1');
      expect(networks.first.connectedContainers, 2);
      expect(networks.first.connectedContainerNames, ['api', 'web']);
    });

    test('maps volume summaries into ui rows', () {
      final volumes = mapper.mapVolumeSummaries([
        {
          'Name': 'app-data',
          'Driver': 'local',
          'Scope': 'local',
          'Mountpoint': '/var/lib/docker/volumes/app-data/_data',
          'CreatedAt': '2024-03-01T10:20:30Z',
          'UsageData': {'RefCount': 3},
        },
      ]);

      expect(volumes, hasLength(1));
      expect(volumes.first.name, 'app-data');
      expect(
        volumes.first.mountpoint,
        '/var/lib/docker/volumes/app-data/_data',
      );
      expect(volumes.first.refCount, 3);
    });

    test('builds create network request body from ui payload', () {
      final request = mapper.buildCreateNetworkRequest({
        'name': 'edge-network',
        'driver': 'bridge',
        'internal': true,
        'attachable': true,
        'options': {'com.docker.network.bridge.enable_icc': 'true'},
        'labels': {'app': 'host-deck'},
      });

      expect(request, {
        'Name': 'edge-network',
        'Driver': 'bridge',
        'CheckDuplicate': true,
        'Internal': true,
        'Attachable': true,
        'Options': {'com.docker.network.bridge.enable_icc': 'true'},
        'Labels': {'app': 'host-deck'},
      });
    });

    test('builds create volume request body from ui payload', () {
      final request = mapper.buildCreateVolumeRequest({
        'name': 'cache-data',
        'driver': 'local',
        'options': {'type': 'nfs'},
        'labels': {'app': 'host-deck'},
      });

      expect(request, {
        'Name': 'cache-data',
        'Driver': 'local',
        'DriverOpts': {'type': 'nfs'},
        'Labels': {'app': 'host-deck'},
      });
    });
  });

  dockerLogTests();
  dockerServiceNetworkTests();
}

class _FakeSshRepository extends SshRepository {}

class _FakeSshSession implements SshSession {
  @override
  final String id = 'session-1';

  @override
  final String connectionId = 'connection-1';

  @override
  SSHClient get client => throw UnimplementedError();

  @override
  SSHSession? get shell => null;

  @override
  final SshOperationLimiter operationLimiter = SshOperationLimiter(
    maxConcurrentOperations: 4,
  );

  @override
  Stream<String> get output => const Stream.empty();

  @override
  StreamController<String> get outputController => StreamController.broadcast();

  @override
  Future<SftpClient> sftp() => throw UnimplementedError();

  @override
  Future<SshOperationPermit> acquireOperation() => operationLimiter.acquire();

  @override
  Future<T> runOperation<T>(FutureOr<T> Function() action) {
    return operationLimiter.run(action);
  }

  @override
  Future<void> close() async {}
}

class _FakeDockerEngineRepository extends DockerEngineRepository {
  _FakeDockerEngineRepository({
    required this.jsonLists,
    required this.jsonObjects,
  }) : super(_FakeSshRepository());

  final Map<String, List<dynamic>> jsonLists;
  final Map<String, Map<String, dynamic>> jsonObjects;
  final requestedObjects = <String>[];
  final requestedRequests = <String>[];

  @override
  Future<DockerEngineResponse> request(
    SshSession session, {
    required String method,
    required String path,
    Map<String, String>? queryParameters,
    Object? body,
    Map<String, String>? headers,
  }) async {
    requestedRequests.add('$method $path');
    return DockerEngineResponse(
      statusCode: 200,
      bodyBytes: Uint8List.fromList(const []),
    );
  }

  @override
  Future<List<dynamic>> requestJsonList(
    SshSession session, {
    required String method,
    required String path,
    Map<String, String>? queryParameters,
    Object? body,
    Map<String, String>? headers,
  }) async {
    final result = jsonLists[path];
    if (result == null) {
      throw Exception('Unexpected JSON list request: $path');
    }
    return result;
  }

  @override
  Future<Map<String, dynamic>> requestJsonObject(
    SshSession session, {
    required String method,
    required String path,
    Map<String, String>? queryParameters,
    Object? body,
    Map<String, String>? headers,
  }) async {
    requestedObjects.add(path);
    final result = jsonObjects[path];
    if (result == null) {
      throw Exception('Unexpected JSON object request: $path');
    }
    return result;
  }
}

void dockerLogTests() {
  group('DockerService logs decoding', () {
    final service = DockerService(_FakeSshRepository());

    test('returns plain utf8 logs when stream is not multiplexed', () {
      final result = service.debugDecodeDockerLogs(
        Uint8List.fromList('plain log output'.codeUnits),
      );

      expect(result, 'plain log output');
    });

    test('decodes docker multiplexed stdout and stderr frames', () {
      final bytes = Uint8List.fromList([
        1,
        0,
        0,
        0,
        0,
        0,
        0,
        6,
        ...'hello\n'.codeUnits,
        2,
        0,
        0,
        0,
        0,
        0,
        0,
        6,
        ...'error\n'.codeUnits,
      ]);

      final result = service.debugDecodeDockerLogs(bytes);
      expect(result, 'hello\nerror\n');
    });
  });
}

void dockerServiceNetworkTests() {
  group('DockerService networks', () {
    test('uses inspected network details for connected containers', () async {
      final engineRepository = _FakeDockerEngineRepository(
        jsonLists: {
          '/networks': [
            {
              'Id': 'network-1',
              'Name': 'app-network',
              'Driver': 'bridge',
              'Scope': 'local',
            },
          ],
        },
        jsonObjects: {
          '/networks/network-1': {
            'Id': 'network-1',
            'Name': 'app-network',
            'Driver': 'bridge',
            'Scope': 'local',
            'Containers': {
              'container-1': {'Name': 'web'},
              'container-2': {'Name': 'api'},
            },
          },
        },
      );
      final service = DockerService(
        _FakeSshRepository(),
        engineRepository: engineRepository,
      );

      final networks = await service.listNetworks(_FakeSshSession());

      expect(engineRepository.requestedObjects, ['/networks/network-1']);
      expect(networks, hasLength(1));
      expect(networks.first.connectedContainers, 2);
      expect(networks.first.connectedContainerNames, ['api', 'web']);
    });

    test('rejects removal of built-in networks', () async {
      final engineRepository = _FakeDockerEngineRepository(
        jsonLists: {},
        jsonObjects: {
          '/networks/default-network': {'Name': 'bridge'},
        },
      );
      final service = DockerService(
        _FakeSshRepository(),
        engineRepository: engineRepository,
      );

      await expectLater(
        service.removeNetwork(_FakeSshSession(), 'default-network'),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'Docker 初始网络不可删除。',
          ),
        ),
      );

      expect(engineRepository.requestedRequests, isEmpty);
    });
  });
}
