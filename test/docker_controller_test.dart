import 'dart:async';
import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:host_deck/server/core/ssh/ssh_operation_limiter.dart';
import 'package:host_deck/server/core/ssh/ssh_repository.dart';
import 'package:host_deck/server/core/ssh/ssh_service.dart';
import 'package:host_deck/server/core/ssh/ssh_session.dart';
import 'package:host_deck/server/features/docker/docker_compose_service.dart';
import 'package:host_deck/server/features/docker/docker_container_service.dart';
import 'package:host_deck/server/features/docker/docker_controller.dart';
import 'package:host_deck/server/features/docker/docker_engine_mapper.dart';
import 'package:host_deck/server/features/docker/docker_engine_repository.dart';
import 'package:host_deck/server/features/docker/docker_image_service.dart';
import 'package:host_deck/server/features/docker/docker_resource_service.dart';
import 'package:shelf/shelf.dart';

void main() {
  test('streams stats with immediate unbuffered connected event', () async {
    final session = _FakeSshSession();
    final sshService = _FakeSshService(session);
    final repository = DockerEngineRepository();
    addTearDown(repository.close);
    final mapper = DockerEngineMapper();
    final controller = DockerController(
      sshService,
      _FakeDockerContainerService(repository, mapper),
      DockerImageService(repository, mapper),
      DockerResourceService(repository, mapper),
      DockerComposeService(SshRepository()),
    );

    final response = await controller.streamContainerStats(
      Request(
        'GET',
        Uri.parse(
          'http://localhost/api/docker/containers/container-1/stats/stream'
          '?sessionId=session-1',
        ),
      ),
      'container-1',
    );

    expect(response.statusCode, 200);
    expect(
      response.headers['content-type'],
      'text/event-stream; charset=utf-8',
    );
    expect(response.headers['cache-control'], 'no-cache, no-transform');
    expect(response.headers['x-accel-buffering'], 'no');
    expect(response.context['shelf.io.buffer_output'], isFalse);

    final iterator = StreamIterator<List<int>>(response.read());
    expect(await iterator.moveNext(), isTrue);
    final initialChunk = utf8.decode(iterator.current);
    expect(initialChunk, startsWith(': '));
    expect(initialChunk, endsWith('event: connected\ndata: {}\n\n'));
    await iterator.cancel();
  });
}

class _FakeDockerContainerService extends DockerContainerService {
  _FakeDockerContainerService(super.engineRepository, super.mapper);

  @override
  Stream<DockerContainerStatsEvent> streamContainerStats(
    SshSession session,
    String containerId,
  ) => const Stream.empty();
}

class _FakeSshService extends SshService {
  final SshSession session;

  _FakeSshService(this.session);

  @override
  SshSession? getSession(String id) => id == session.id ? session : null;
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
