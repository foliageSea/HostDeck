import 'package:flutter_test/flutter_test.dart';
import 'package:ssh_tool/server/services/docker_engine_mapper.dart';
import 'dart:typed_data';

import 'package:ssh_tool/server/repositories/ssh_repository.dart';
import 'package:ssh_tool/server/services/docker_service.dart';

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
  });

  dockerLogTests();
}

class _FakeSshRepository extends SshRepository {}

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
