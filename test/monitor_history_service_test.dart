import 'package:flutter_test/flutter_test.dart';
import 'package:host_deck/server/models/system_status.dart';
import 'package:host_deck/server/services/monitor_history_service.dart';

SystemStatus buildStatus(int timestamp, {double cpuUsage = 10}) {
  return SystemStatus(
    timestamp: timestamp,
    cpu: '0.10',
    cpuUsage: cpuUsage,
    ram: RamStatus(total: 8000, used: 4000),
    disk: '45%',
    network: NetworkStatus(uploadSpeed: 120, downloadSpeed: 240),
  );
}

void main() {
  test('MonitorHistoryService keeps history per connection', () {
    final now = DateTime.now().millisecondsSinceEpoch;
    final service = MonitorHistoryService(maxSamplesPerConnection: 10);

    service.addSample('conn-a', buildStatus(now, cpuUsage: 11));
    service.addSample('conn-b', buildStatus(now + 1, cpuUsage: 22));

    expect(service.getHistory('conn-a').map((item) => item.cpuUsage), [11]);
    expect(service.getHistory('conn-b').map((item) => item.cpuUsage), [22]);
  });

  test('MonitorHistoryService trims to max sample count', () {
    final now = DateTime.now().millisecondsSinceEpoch;
    final service = MonitorHistoryService(maxSamplesPerConnection: 2);

    service.addSample('conn-a', buildStatus(now, cpuUsage: 11));
    service.addSample('conn-a', buildStatus(now + 1, cpuUsage: 22));
    service.addSample('conn-a', buildStatus(now + 2, cpuUsage: 33));

    final history = service.getHistory('conn-a');
    expect(history.map((item) => item.cpuUsage), [22, 33]);
  });

  test('MonitorHistoryService applies requested limit', () {
    final now = DateTime.now().millisecondsSinceEpoch;
    final service = MonitorHistoryService(maxSamplesPerConnection: 10);

    service.addSample('conn-a', buildStatus(now, cpuUsage: 11));
    service.addSample('conn-a', buildStatus(now + 1, cpuUsage: 22));
    service.addSample('conn-a', buildStatus(now + 2, cpuUsage: 33));

    final history = service.getHistory('conn-a', limit: 2);
    expect(history.map((item) => item.cpuUsage), [22, 33]);
  });
}
