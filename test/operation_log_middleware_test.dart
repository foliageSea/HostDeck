import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart';

import 'package:host_deck/server/core/database/database_service.dart';
import 'package:host_deck/server/core/http/result.dart';
import 'package:host_deck/server/features/operation_logs/operation_log_middleware.dart';
import 'package:host_deck/server/features/operation_logs/operation_log_repository.dart';
import 'package:host_deck/server/features/operation_logs/operation_log_service.dart';
import 'package:host_deck/server/features/servers/server_config.dart';
import 'package:host_deck/server/features/servers/server_repository.dart';

void main() {
  group('operationLogMiddleware', () {
    late DatabaseService databaseService;
    late Directory dataDirectory;
    late OperationLogRepository repository;
    late ServerRepository serverRepository;
    late Handler handler;

    setUp(() async {
      dataDirectory = await Directory.systemTemp.createTemp('host_deck_test_');
      databaseService = DatabaseService(dataDir: dataDirectory.path);
      await databaseService.init();
      repository = OperationLogRepository(databaseService);
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
  });
}
