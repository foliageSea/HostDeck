class ServerMetricsSnapshot {
  final int timestamp;
  final int uptimeMs;
  final int rssBytes;
  final int peakRssBytes;
  final double? cpuPercent;
  final double eventLoopLagMs;

  const ServerMetricsSnapshot({
    required this.timestamp,
    required this.uptimeMs,
    required this.rssBytes,
    required this.peakRssBytes,
    required this.cpuPercent,
    required this.eventLoopLagMs,
  });

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp,
    'uptimeMs': uptimeMs,
    'rssBytes': rssBytes,
    'peakRssBytes': peakRssBytes,
    'cpuPercent': cpuPercent,
    'eventLoopLagMs': eventLoopLagMs,
  };
}
