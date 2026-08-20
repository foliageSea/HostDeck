import 'package:flutter_test/flutter_test.dart';
import 'package:host_deck/server/app/server_logging.dart';
import 'package:host_deck/server/features/logs/server_log_entry.dart';

void main() {
  final entry = ServerLogEntry(
    id: 1,
    timestamp: DateTime.utc(2026),
    level: 'INFO',
    levelValue: 800,
    logger: 'DockerSocketTunnelService',
    message: 'Tunnel created',
  );

  test('truncates long logger names in file logs', () {
    expect(
      formatServerLogEntry(entry),
      contains('DockerSocketTunnelSer... | Tunnel created'),
    );
  });

  test('truncates long logger names in console logs', () {
    expect(
      formatConsoleServerLogEntry(entry),
      contains('DockerSocketTunnelSer... | Tunnel created'),
    );
  });
}
