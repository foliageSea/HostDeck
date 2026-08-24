import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:host_deck/server/core/ssh/ssh_operation_limiter.dart';
import 'package:host_deck/server/core/ssh/ssh_session.dart';
import 'package:host_deck/server/features/docker/docker_engine_repository.dart';

void main() {
  late HttpServer server;
  late DockerEngineRepository repository;
  final session = _FakeSshSession();

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    repository = DockerEngineRepository(
      endpointProvider: (_) async =>
          Uri.parse('http://${server.address.address}:${server.port}'),
    );
  });

  tearDown(() => server.close(force: true));

  test('sends JSON requests and decodes object responses', () async {
    server.listen((request) async {
      expect(request.uri.path, '/containers/create');
      expect(request.uri.queryParameters, {'name': 'web'});
      expect(request.headers.contentType?.mimeType, 'application/json');
      expect(await utf8.decoder.bind(request).join(), '{"Image":"nginx"}');
      request.response
        ..statusCode = HttpStatus.created
        ..write('{"Id":"abc"}');
      await request.response.close();
    });

    final result = await repository.requestJsonObject(
      session,
      method: 'POST',
      path: '/containers/create',
      queryParameters: {'name': 'web'},
      body: {'Image': 'nginx'},
    );

    expect(result, {'Id': 'abc'});
  });

  test('preserves encoded Engine path segments', () async {
    server.listen((request) async {
      expect(request.uri.path, '/images/example%3Alatest/json');
      expect(request.uri.toString(), '/images/example%3Alatest/json');
      request.response.write('{}');
      await request.response.close();
    });

    await repository.requestJsonObject(
      session,
      method: 'GET',
      path: '/images/example%3Alatest/json',
    );
  });

  test('streams request body without buffering', () async {
    final received = Completer<List<int>>();
    server.listen((request) async {
      received.complete(
        await request.fold<List<int>>([], (a, b) => a..addAll(b)),
      );
      request.response.write('{"stream":"Loaded image"}\n');
      await request.response.close();
    });

    final response = await repository.requestText(
      session,
      method: 'POST',
      path: '/images/load',
      body: Stream<List<int>>.fromIterable([
        [1, 2],
        [3, 4],
      ]),
      headers: {'Content-Type': 'application/x-tar'},
    );

    expect(await received.future, [1, 2, 3, 4]);
    expect(response, contains('Loaded image'));
  });

  test('exposes a streaming binary response', () async {
    server.listen((request) async {
      request.response.add([1, 2]);
      await request.response.flush();
      request.response.add([3, 4]);
      await request.response.close();
    });

    final stream = await repository.requestByteStream(
      session,
      method: 'GET',
      path: '/images/nginx/get',
    );

    expect(await stream.expand((chunk) => chunk).toList(), [1, 2, 3, 4]);
  });

  test('times out while waiting for streaming response headers', () async {
    final received = Completer<void>();
    server.listen((_) {
      received.complete();
    });

    final response = repository.requestByteStream(
      session,
      method: 'GET',
      path: '/containers/container-1/stats',
      responseTimeout: const Duration(milliseconds: 50),
    );

    await received.future;
    await expectLater(response, throwsA(isA<TimeoutException>()));
  });

  test('maps Engine API errors to DockerEngineHttpException', () async {
    server.listen((request) async {
      request.response
        ..statusCode = HttpStatus.notFound
        ..write('{"message":"No such image"}');
      await request.response.close();
    });

    await expectLater(
      repository.request(session, method: 'GET', path: '/images/missing/json'),
      throwsA(
        isA<DockerEngineHttpException>()
            .having((error) => error.statusCode, 'statusCode', 404)
            .having((error) => error.message, 'message', 'No such image'),
      ),
    );
  });

  test('requestStream emits body and HTTP completion contract', () async {
    server.listen((request) async {
      request.response.write('{"status":"Pulling"}\n');
      await request.response.close();
    });

    final events = await repository
        .requestStream(session, method: 'POST', path: '/images/create')
        .toList();

    expect(events.first.source, DockerEngineStreamSource.body);
    expect(events.first.text, contains('Pulling'));
    expect(events.last.completed, isTrue);
    expect(events.last.statusCode, 200);
    expect(events.last.exitCode, 0);
  });
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
