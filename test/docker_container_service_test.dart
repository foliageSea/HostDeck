import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:host_deck/server/core/ssh/ssh_operation_limiter.dart';
import 'package:host_deck/server/core/ssh/ssh_session.dart';
import 'package:host_deck/server/features/docker/docker_container_service.dart';
import 'package:host_deck/server/features/docker/docker_engine_mapper.dart';
import 'package:host_deck/server/features/docker/docker_engine_repository.dart';

void main() {
  group('DockerContainerService logs decoding', () {
    final service = DockerContainerService(
      DockerEngineRepository(),
      DockerEngineMapper(),
    );

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

    test('streams multiplexed frames split across chunks', () async {
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
      final chunks = <Uint8List>[
        Uint8List.sublistView(bytes, 0, 3),
        Uint8List.sublistView(bytes, 3, 11),
        Uint8List.sublistView(bytes, 11, 19),
        Uint8List.sublistView(bytes, 19),
      ];

      final events = await service
          .decodeDockerLogStream(Stream.fromIterable(chunks), multiplexed: true)
          .toList();

      expect(events.map((event) => event.event), ['stdout', 'stderr']);
      expect(events.map((event) => event.text), ['hello\n', 'error\n']);
    });

    test('preserves utf8 characters split across raw chunks', () async {
      final bytes = Uint8List.fromList(utf8.encode('日志输出'));
      final chunks = <Uint8List>[
        Uint8List.sublistView(bytes, 0, 1),
        Uint8List.sublistView(bytes, 1, 4),
        Uint8List.sublistView(bytes, 4),
      ];

      final events = await service
          .decodeDockerLogStream(
            Stream.fromIterable(chunks),
            multiplexed: false,
          )
          .toList();

      expect(events.map((event) => event.text).join(), '日志输出');
    });

    test('rejects an incomplete multiplexed frame', () async {
      final stream = service.decodeDockerLogStream(
        Stream.value(Uint8List.fromList([1, 0, 0, 0, 0, 0, 0, 4, 65])),
        multiplexed: true,
      );

      await expectLater(stream.toList(), throwsA(isA<FormatException>()));
    });

    test('follows the Docker Engine log stream', () async {
      final repository = _LogsDockerEngineRepository();
      final logService = DockerContainerService(
        repository,
        DockerEngineMapper(),
      );

      final events = await logService
          .getContainerLogs(_FakeSshSession(), 'container-1')
          .toList();

      expect(repository.queryParameters?['follow'], '1');
      expect(events.single.text, 'hello\n');
    });

    test('fetches a finite Docker Engine log snapshot', () async {
      final repository = _LogsDockerEngineRepository();
      final logService = DockerContainerService(
        repository,
        DockerEngineMapper(),
      );

      final events = await logService
          .getContainerLogs(
            _FakeSshSession(),
            'container-1',
            tail: 200,
            follow: false,
          )
          .toList();

      expect(repository.queryParameters?['tail'], '200');
      expect(repository.queryParameters?['follow'], '0');
      expect(events.single.text, 'hello\n');
    });
  });

  group('DockerContainerService stats streaming', () {
    test('maps streamed samples and calculates network rates', () async {
      final repository = _StatsDockerEngineRepository();
      final service = DockerContainerService(repository, DockerEngineMapper());

      final events = await service
          .streamContainerStats(_FakeSshSession(), 'container-1')
          .toList();

      expect(repository.queryParameters, {'stream': 'true'});
      expect(events, hasLength(2));
      expect(events.first.data['networkRxBytesPerSecond'], 0);
      expect(events.last.data['networkRxBytesPerSecond'], 1024);
      expect(events.last.data['networkTxBytesPerSecond'], 2048);
    });
  });

  group('DockerContainerService replacement', () {
    test('replaces a stopped container and removes the original', () async {
      final repository = _FakeDockerEngineRepository();
      final service = DockerContainerService(repository, DockerEngineMapper());

      final result = await service.replaceContainer(
        _FakeSshSession(),
        'old-id',
        {
          'image': 'nginx:latest',
          'name': 'web',
          'ports': ['8080:80'],
          'start': false,
        },
      );

      expect(result['newContainerId'], 'new-id');
      expect(repository.createdName, 'web');
      expect(repository.removedIds, ['old-id']);
      expect(repository.renames.first.$1, 'old-id');
    });

    test(
      'restores the original name when replacement creation fails',
      () async {
        final repository = _FakeDockerEngineRepository(failCreate: true);
        final service = DockerContainerService(
          repository,
          DockerEngineMapper(),
        );

        await expectLater(
          service.replaceContainer(_FakeSshSession(), 'old-id', {
            'image': 'nginx:latest',
            'name': 'web',
            'start': false,
          }),
          throwsException,
        );

        expect(repository.removedIds, isEmpty);
        expect(repository.renames.last, ('old-id', 'web'));
      },
    );

    test(
      'removes the replacement and restores the original when start fails',
      () async {
        final repository = _FakeDockerEngineRepository(failStart: true);
        final service = DockerContainerService(
          repository,
          DockerEngineMapper(),
        );

        await expectLater(
          service.replaceContainer(_FakeSshSession(), 'old-id', {
            'image': 'nginx:latest',
            'name': 'web',
            'start': true,
          }),
          throwsException,
        );

        expect(repository.removedIds, ['new-id']);
        expect(repository.renames.last, ('old-id', 'web'));
      },
    );

    test('rejects editing a running container', () async {
      final repository = _FakeDockerEngineRepository(running: true);
      final service = DockerContainerService(repository, DockerEngineMapper());

      await expectLater(
        service.replaceContainer(_FakeSshSession(), 'old-id', {
          'image': 'nginx:latest',
          'name': 'web',
        }),
        throwsA(isA<StateError>()),
      );

      expect(repository.renames, isEmpty);
    });
  });
}

class _FakeDockerEngineRepository extends DockerEngineRepository {
  final bool failCreate;
  final bool failStart;
  final bool running;
  final List<(String, String)> renames = [];
  final List<String> removedIds = [];
  String? createdName;

  _FakeDockerEngineRepository({
    this.failCreate = false,
    this.failStart = false,
    this.running = false,
  });

  @override
  Future<Map<String, dynamic>> requestJsonObject(
    SshSession session, {
    required String method,
    required String path,
    Map<String, String>? queryParameters,
    Object? body,
    Map<String, String>? headers,
  }) async {
    if (method == 'GET' && path == '/containers/old-id/json') {
      return {
        'Name': '/web',
        'State': {'Running': running},
      };
    }
    if (method == 'POST' && path == '/containers/create') {
      createdName = queryParameters?['name'];
      if (failCreate) {
        throw Exception('create failed');
      }
      return {'Id': 'new-id'};
    }
    throw UnimplementedError('$method $path');
  }

  @override
  Future<DockerEngineResponse> request(
    SshSession session, {
    required String method,
    required String path,
    Map<String, String>? queryParameters,
    Object? body,
    Map<String, String>? headers,
  }) async {
    if (method == 'POST' && path.endsWith('/rename')) {
      renames.add((path.split('/')[2], queryParameters!['name']!));
    } else if (method == 'POST' && path == '/containers/new-id/start') {
      if (failStart) {
        throw Exception('start failed');
      }
    } else if (method == 'DELETE') {
      removedIds.add(path.split('/')[2]);
    } else {
      throw UnimplementedError('$method $path');
    }
    return DockerEngineResponse(statusCode: 204, bodyBytes: Uint8List(0));
  }
}

class _StatsDockerEngineRepository extends DockerEngineRepository {
  Map<String, String>? queryParameters;

  @override
  Future<Stream<Uint8List>> requestByteStream(
    SshSession session, {
    required String method,
    required String path,
    Map<String, String>? queryParameters,
    Object? body,
    Map<String, String>? headers,
    Duration? responseTimeout,
  }) async {
    this.queryParameters = queryParameters;
    final first = _statsPayload(
      '2026-08-13T10:00:00.000Z',
      rxBytes: 1024,
      txBytes: 2048,
    );
    final second = _statsPayload(
      '2026-08-13T10:00:01.000Z',
      rxBytes: 2048,
      txBytes: 4096,
    );
    final bytes = Uint8List.fromList(utf8.encode('$first\n$second\n'));
    return Stream.fromIterable([
      Uint8List.sublistView(bytes, 0, 17),
      Uint8List.sublistView(bytes, 17),
    ]);
  }

  String _statsPayload(
    String read, {
    required int rxBytes,
    required int txBytes,
  }) {
    return jsonEncode({
      'id': 'container-1',
      'name': '/web',
      'read': read,
      'cpu_stats': {
        'system_cpu_usage': 2000,
        'online_cpus': 2,
        'cpu_usage': {'total_usage': 400},
      },
      'precpu_stats': {
        'system_cpu_usage': 1000,
        'cpu_usage': {'total_usage': 200},
      },
      'memory_stats': {'usage': 300, 'limit': 1000, 'stats': {}},
      'networks': {
        'eth0': {'rx_bytes': rxBytes, 'tx_bytes': txBytes},
      },
      'pids_stats': {'current': 4},
    });
  }
}

class _LogsDockerEngineRepository extends DockerEngineRepository {
  Map<String, String>? queryParameters;

  @override
  Future<Map<String, dynamic>> requestJsonObject(
    SshSession session, {
    required String method,
    required String path,
    Map<String, String>? queryParameters,
    Object? body,
    Map<String, String>? headers,
  }) async {
    return {
      'Config': {'Tty': true},
    };
  }

  @override
  Future<Stream<Uint8List>> requestByteStream(
    SshSession session, {
    required String method,
    required String path,
    Map<String, String>? queryParameters,
    Object? body,
    Map<String, String>? headers,
    Duration? responseTimeout,
  }) async {
    this.queryParameters = queryParameters;
    return Stream.value(Uint8List.fromList(utf8.encode('hello\n')));
  }
}

class _FakeSshSession implements SshSession {
  @override
  String get id => 'session-1';
  @override
  String get connectionId => 'connection-1';
  @override
  SSHClient get client => throw UnimplementedError();
  @override
  SSHSession? get shell => null;
  @override
  final SshOperationLimiter operationLimiter = SshOperationLimiter(
    maxConcurrentOperations: 1,
  );
  @override
  Stream<String> get output => const Stream.empty();
  @override
  StreamController<String> get outputController => StreamController.broadcast();
  @override
  Future<SshOperationPermit> acquireOperation() => operationLimiter.acquire();
  @override
  Future<T> runOperation<T>(FutureOr<T> Function() action) =>
      operationLimiter.run(action);
  @override
  Future<SftpClient> sftp() => throw UnimplementedError();
  @override
  Future<void> close() async {}
}
