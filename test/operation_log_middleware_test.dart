import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart';

import 'package:host_deck/server/core/database/database_service.dart';
import 'package:host_deck/server/core/http/result.dart';
import 'package:host_deck/server/features/operation_logs/operation_log_middleware.dart';
import 'package:host_deck/server/features/operation_logs/operation_log_repository.dart';
import 'package:host_deck/server/features/operation_logs/operation_log_service.dart';
import 'package:host_deck/server/features/port_forwards/port_forward_repository.dart';
import 'package:host_deck/server/features/port_forwards/port_forward_rule.dart';
import 'package:host_deck/server/features/servers/server_config.dart';
import 'package:host_deck/server/features/servers/server_repository.dart';

void main() {
  group('operationLogMiddleware', () {
    late DatabaseService databaseService;
    late Directory dataDirectory;
    late OperationLogRepository repository;
    late PortForwardRepository portForwardRepository;
    late ServerRepository serverRepository;
    late Handler handler;

    setUp(() async {
      dataDirectory = await Directory.systemTemp.createTemp('host_deck_test_');
      databaseService = DatabaseService(dataDir: dataDirectory.path);
      await databaseService.init();
      repository = OperationLogRepository(databaseService);
      portForwardRepository = PortForwardRepository(databaseService);
      serverRepository = ServerRepository(databaseService);
    });

    tearDown(() async {
      databaseService.close();
      await dataDirectory.delete(recursive: true);
    });

    test('records success and preserves the JSON request body', () async {
      handler =
          operationLogMiddleware(
            OperationLogService(repository),
            serverRepository,
            portForwardRepository,
          )((request) async {
            expect(
              await request.readAsString(),
              '{"command":"pwd","connectionId":"c1"}',
            );
            return Result.ok({'success': true});
          });

      final response = await handler(
        Request(
          'POST',
          Uri.parse('http://localhost/api/agent/exec'),
          body: '{"command":"pwd","connectionId":"c1"}',
          headers: {'content-type': 'application/json'},
        ),
      );

      expect(response.statusCode, 200);
      final log = repository.list().single;
      expect(log.category, 'agent');
      expect(log.action, 'exec');
      expect(log.target, 'pwd');
      expect(log.connectionId, 'c1');
      expect(log.status, 'success');
    });

    test('records failures and preserves the error response body', () async {
      handler =
          operationLogMiddleware(
            OperationLogService(repository),
            serverRepository,
            portForwardRepository,
          )((request) async {
            return Result.fail(404, 'Server not found');
          });

      final response = await handler(
        Request('DELETE', Uri.parse('http://localhost/api/servers/42')),
      );

      expect(response.statusCode, 404);
      expect(await response.readAsString(), contains('Server not found'));
      final log = repository.list().single;
      expect(log.category, 'server');
      expect(log.action, 'delete');
      expect(log.target, '42');
      expect(log.status, 'failed');
      expect(log.errorMessage, 'Server not found');
    });

    test('records an SSE operation only after its done event', () async {
      handler =
          operationLogMiddleware(
            OperationLogService(repository),
            serverRepository,
            portForwardRepository,
          )((request) {
            return Response.ok(
              Stream<List<int>>.fromIterable([
                utf8.encode('event: progress\ndata: {}\n\n'),
                utf8.encode('event: done\ndata: {"image":"alpine"}\n\n'),
              ]),
              headers: {'content-type': 'text/event-stream'},
            );
          });

      final response = await handler(
        Request(
          'POST',
          Uri.parse(
            'http://localhost/api/docker/images/pull/stream?connectionId=c1',
          ),
          body: '{"image":"alpine"}',
          headers: {'content-type': 'application/json'},
        ),
      );

      expect(repository.list(), isEmpty);
      await response.readAsString();
      final log = repository.list().single;
      expect(log.action, 'imagePull');
      expect(log.target, 'alpine');
      expect(log.connectionId, 'c1');
      expect(log.status, 'success');
    });

    test('records an SSE error event as a failure', () async {
      handler =
          operationLogMiddleware(
            OperationLogService(repository),
            serverRepository,
            portForwardRepository,
          )((request) {
            return Response.ok(
              Stream<List<int>>.value(
                utf8.encode('event: error\ndata: {"message":"denied"}\n\n'),
              ),
              headers: {'content-type': 'text/event-stream'},
            );
          });

      final response = await handler(
        Request(
          'POST',
          Uri.parse('http://localhost/api/docker/images/pull/stream'),
          body: '{"image":"private/app"}',
          headers: {'content-type': 'application/json'},
        ),
      );

      await response.readAsString();
      final log = repository.list().single;
      expect(log.action, 'imagePull');
      expect(log.status, 'failed');
    });

    test('records compose project creation after its done event', () async {
      handler =
          operationLogMiddleware(
            OperationLogService(repository),
            serverRepository,
            portForwardRepository,
          )((request) {
            return Response.ok(
              Stream<List<int>>.value(
                utf8.encode('event: done\ndata: {"projectName":"website"}\n\n'),
              ),
              headers: {'content-type': 'text/event-stream'},
            );
          });

      final response = await handler(
        Request(
          'POST',
          Uri.parse(
            'http://localhost/api/docker/compose/project/stream?connectionId=c1',
          ),
          body: '{"projectName":"website","workingDir":"/srv/website"}',
          headers: {'content-type': 'application/json'},
        ),
      );

      expect(repository.list(), isEmpty);
      await response.readAsString();
      final log = repository.list().single;
      expect(log.action, 'composeCreate');
      expect(log.target, 'website');
      expect(log.connectionId, 'c1');
      expect(log.status, 'success');
    });

    test('records compose project lifecycle operations', () async {
      handler = operationLogMiddleware(
        OperationLogService(repository),
        serverRepository,
        portForwardRepository,
      )((request) => Result.ok({'success': true}));
      const actions = ['up', 'stop', 'restart', 'down'];

      for (final action in actions) {
        await handler(
          Request(
            'POST',
            Uri.parse(
              'http://localhost/api/docker/compose/project/$action?connectionId=c1',
            ),
            body: '{"projectName":"website","configFiles":["compose.yml"]}',
            headers: {'content-type': 'application/json'},
          ),
        );
      }

      final logs = repository.list();
      expect(
        logs.map((log) => log.action),
        containsAll([
          'composeUp',
          'composeStop',
          'composeRestart',
          'composeDown',
        ]),
      );
      expect(logs.map((log) => log.target), everyElement('website'));
      expect(logs.map((log) => log.connectionId), everyElement('c1'));
      expect(logs.map((log) => log.status), everyElement('success'));
    });

    test('uses the saved host address for a connection target', () async {
      final server = serverRepository.addServer(
        ServerConfig(
          name: 'Production',
          host: 'prod.example.com',
          port: 2222,
          username: 'deploy',
        ),
      );
      handler = operationLogMiddleware(
        OperationLogService(repository),
        serverRepository,
        portForwardRepository,
      )((request) => Result.ok({'connectionId': 'c1'}));

      await handler(
        Request(
          'POST',
          Uri.parse('http://localhost/api/connect'),
          body: '{"serverId":${server.id}}',
          headers: {'content-type': 'application/json'},
        ),
      );

      expect(repository.list().single.target, 'deploy@prod.example.com:2222');
    });

    test('formats a port-forward rule as its target', () async {
      handler = operationLogMiddleware(
        OperationLogService(repository),
        serverRepository,
        portForwardRepository,
      )((request) => Result.ok({'success': true}));

      await handler(
        Request(
          'POST',
          Uri.parse('http://localhost/api/port-forwards'),
          body:
              '{"bindHost":"127.0.0.1","localPort":8080,"remoteHost":"db.internal","remotePort":5432}',
          headers: {'content-type': 'application/json'},
        ),
      );

      expect(
        repository.list().single.target,
        '127.0.0.1:8080 -> db.internal:5432',
      );
    });

    test(
      'formats an existing port-forward rule for lifecycle operations',
      () async {
        final rule = portForwardRepository.addRule(
          const PortForwardRule(
            name: 'Database',
            enabled: false,
            bindHost: '127.0.0.1',
            localPort: 15432,
            remoteHost: 'db.internal',
            remotePort: 5432,
          ),
        );
        handler = operationLogMiddleware(
          OperationLogService(repository),
          serverRepository,
          portForwardRepository,
        )((request) => Result.ok({'success': true}));

        await handler(
          Request(
            'POST',
            Uri.parse('http://localhost/api/port-forwards/${rule.id}/start'),
          ),
        );
        await handler(
          Request(
            'POST',
            Uri.parse('http://localhost/api/port-forwards/${rule.id}/stop'),
          ),
        );
        await handler(
          Request(
            'DELETE',
            Uri.parse('http://localhost/api/port-forwards/${rule.id}'),
          ),
        );

        expect(
          repository.list().map((log) => log.target),
          everyElement('127.0.0.1:15432 -> db.internal:5432'),
        );
      },
    );
  });
}
