import 'package:flutter_test/flutter_test.dart';
import 'package:host_deck/server/core/ssh/ssh_service.dart';

void main() {
  test(
    'disconnecting an unknown connection preserves an empty runtime snapshot',
    () async {
      final service = SshService();

      await service.disconnect('missing-connection');

      expect(service.getRuntimeSnapshot(), {
        'totalClients': 0,
        'totalSessions': 0,
        'clients': <Map<String, dynamic>>[],
        'sessions': <Map<String, dynamic>>[],
      });
    },
  );
}
