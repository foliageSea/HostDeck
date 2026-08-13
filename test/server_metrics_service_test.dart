import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:host_deck/server/features/server_metrics/server_metrics_snapshot.dart';
import 'package:host_deck/server/features/server_metrics/server_metrics_service.dart';

void main() {
  test('LinuxProcessCpuSampler calculates normalized CPU usage', () async {
    var sampleIndex = 0;
    final processStats = [
      _processStat(userTicks: 100, systemTicks: 50),
      _processStat(userTicks: 125, systemTicks: 75),
    ];
    final systemStats = [
      'cpu  100 20 30 400 10 0 0 0 0 0\n',
      'cpu  150 20 50 530 10 0 0 0 0 0\n',
    ];
    final sampler = LinuxProcessCpuSampler(
      processorCount: 4,
      readFile: (path) async {
        final value = path == '/proc/self/stat'
            ? processStats[sampleIndex]
            : systemStats[sampleIndex];
        if (path == '/proc/stat') sampleIndex++;
        return value;
      },
    );

    expect(await sampler.sample(), isNull);
    expect(await sampler.sample(), closeTo(100, 0.001));
  });

  test('LinuxProcessCpuSampler tolerates unavailable proc files', () async {
    final sampler = LinuxProcessCpuSampler(
      readFile: (_) async => null,
      processorCount: 1,
    );

    expect(await sampler.sample(), isNull);
  });

  test('ServerMetricsService returns process memory snapshot', () async {
    final service = ServerMetricsService(
      currentRss: () => 1234,
      maxRss: () => 5678,
      enableLinuxCpu: false,
    );
    addTearDown(service.dispose);

    final snapshot = await service.getSnapshot();

    expect(snapshot.rssBytes, 1234);
    expect(snapshot.peakRssBytes, 5678);
    expect(snapshot.cpuPercent, isNull);
    expect(snapshot.uptimeMs, greaterThanOrEqualTo(0));
    expect(snapshot.eventLoopLagMs, greaterThanOrEqualTo(0));
  });

  test('ServerMetricsSnapshot serializes API contract', () {
    const snapshot = ServerMetricsSnapshot(
      timestamp: 1000,
      uptimeMs: 2000,
      rssBytes: 3000,
      peakRssBytes: 4000,
      cpuPercent: 12.5,
      eventLoopLagMs: 1.25,
    );

    expect(jsonEncode(snapshot.toJson()), contains('"cpuPercent":12.5'));
    expect(snapshot.toJson(), {
      'timestamp': 1000,
      'uptimeMs': 2000,
      'rssBytes': 3000,
      'peakRssBytes': 4000,
      'cpuPercent': 12.5,
      'eventLoopLagMs': 1.25,
    });
  });
}

String _processStat({required int userTicks, required int systemTicks}) {
  return '123 (host deck) S 1 2 3 4 5 6 7 8 9 10 $userTicks '
      '$systemTicks 13 14 15 16 17 18 19 20';
}
