import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:host_deck/server/core/ssh/ssh_operation_limiter.dart';
import 'package:host_deck/server/core/ssh/ssh_session.dart';
import 'package:host_deck/server/features/docker/docker_engine_mapper.dart';
import 'package:host_deck/server/features/docker/docker_engine_repository.dart';
import 'package:host_deck/server/features/docker/docker_image_service.dart';

void main() {
  final session = _FakeSshSession();

  test('imports an image through POST /images/load', () async {
    final repository = _FakeDockerEngineRepository();
    final service = DockerImageService(repository, DockerEngineMapper());
    final archive = Stream<List<int>>.value([1, 2, 3]);

    final output = await service.importImage(session, archive);

    expect(output, 'Loaded image: example:latest');
    expect(repository.method, 'POST');
    expect(repository.path, '/images/load');
    expect(repository.body, same(archive));
    expect(repository.headers, {'Content-Type': 'application/x-tar'});
  });

  test('exports an image through the Engine binary stream', () async {
    final repository = _FakeDockerEngineRepository();
    final service = DockerImageService(repository, DockerEngineMapper());

    final stream = await service.exportImage(session, 'example:latest');

    expect(await stream.expand((chunk) => chunk).toList(), [1, 2, 3]);
    expect(repository.method, 'GET');
    expect(repository.path, '/images/example%3Alatest/get');
  });
}

class _FakeDockerEngineRepository extends DockerEngineRepository {
  _FakeDockerEngineRepository() : super();

  String? method;
  String? path;
  Object? body;
  Map<String, String>? headers;

  @override
  Future<String> requestText(
    SshSession session, {
    required String method,
    required String path,
    Map<String, String>? queryParameters,
    Object? body,
    Map<String, String>? headers,
  }) async {
    this.method = method;
    this.path = path;
    this.body = body;
    this.headers = headers;
    return 'Loaded image: example:latest';
  }

  @override
  Future<Stream<Uint8List>> requestByteStream(
    SshSession session, {
    required String method,
    required String path,
    Map<String, String>? queryParameters,
    Object? body,
    Map<String, String>? headers,
  }) async {
    this.method = method;
    this.path = path;
    return Stream.value(Uint8List.fromList([1, 2, 3]));
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
