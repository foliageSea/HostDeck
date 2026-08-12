import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:host_deck/server/core/ssh/ssh_operation_limiter.dart';
import 'package:host_deck/server/core/ssh/ssh_session.dart';
import 'package:host_deck/server/features/docker/docker_engine_mapper.dart';
import 'package:host_deck/server/features/docker/docker_engine_repository.dart';
import 'package:host_deck/server/features/docker/docker_resource_service.dart';

void main() {
  group('DockerResourceService networks', () {
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
      final service = DockerResourceService(
        engineRepository,
        DockerEngineMapper(),
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
      final service = DockerResourceService(
        engineRepository,
        DockerEngineMapper(),
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
  }) : super();

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
