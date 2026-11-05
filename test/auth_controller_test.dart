import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:host_deck/server/core/ssh/ssh_service.dart';
import 'package:host_deck/server/features/auth/auth_controller.dart';
import 'package:host_deck/server/features/servers/server_repository.dart';
import 'package:host_deck/server/features/system/monitor_history_service.dart';
import 'package:host_deck/server/routes/auth_routes.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

void main() {
  late _SshService service;
  late Router router;
  setUp(() {
    service = _SshService();
    router = Router();
    registerAuthRoutes(
      router,
      AuthController(service, MonitorHistoryService(), _ServerRepository()),
    );
  });

  test(
    'routes cancellation by request id and returns unified success',
    () async {
      final response = await router.call(
        Request(
          'DELETE',
          Uri.parse(
            'http://localhost/api/connect/pending?requestId=0123456789abcdef',
          ),
        ),
      );
      expect(
        jsonDecode(await response.readAsString()),
        containsPair('code', 200),
      );
      expect(service.cancelledId, '0123456789abcdef');
    },
  );

  test('rejects missing and malformed cancellation identifiers', () async {
    for (final suffix in ['', '?requestId=short']) {
      final response = await router.call(
        Request(
          'DELETE',
          Uri.parse('http://localhost/api/connect/pending$suffix'),
        ),
      );
      expect(
        jsonDecode(await response.readAsString()),
        containsPair('code', 400),
      );
    }
    expect(service.cancelledId, isNull);
  });

  test(
    'passes request id into SSH connect and maps cancellation to code 499',
    () async {
      final response = await router.call(
        Request(
          'POST',
          Uri.parse('http://localhost/api/connect'),
          body: jsonEncode({
            'host': 'example.com',
            'port': 22,
            'username': 'user',
            'requestId': '0123456789abcdef',
          }),
        ),
      );
      expect(service.requestId, '0123456789abcdef');
      expect(
        jsonDecode(await response.readAsString()),
        containsPair('code', 499),
      );
      expect(response.statusCode, 499);
    },
  );
}

class _ServerRepository implements ServerRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SshService extends SshService {
  String? cancelledId;
  String? requestId;

  @override
  Future<void> cancelConnect(String requestId) async => cancelledId = requestId;

  @override
  Future<String> connect({
    required String host,
    required int port,
    required String username,
    int? serverId,
    String? password,
    String? privateKey,
    String? requestId,
  }) async {
    this.requestId = requestId;
    throw const SshConnectionCancelled();
  }
}
