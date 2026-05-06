import 'dart:collection';

import '../models/system_status.dart';

class _MonitorHistoryBucket {
  final ListQueue<SystemStatus> samples = ListQueue<SystemStatus>();
  DateTime lastUpdatedAt;

  _MonitorHistoryBucket(this.lastUpdatedAt);
}

class MonitorHistoryService {
  final Duration retention;
  final int maxSamplesPerConnection;
  final Map<String, _MonitorHistoryBucket> _buckets = {};

  MonitorHistoryService({
    this.retention = const Duration(minutes: 10),
    this.maxSamplesPerConnection = 240,
  });

  void addSample(String connectionId, SystemStatus status) {
    final now = DateTime.now();
    _cleanupExpiredBuckets(now);

    final bucket = _buckets.putIfAbsent(
      connectionId,
      () => _MonitorHistoryBucket(now),
    );

    bucket.lastUpdatedAt = now;
    bucket.samples.addLast(status);
    _trimBucket(bucket, now);
  }

  List<SystemStatus> getHistory(String connectionId, {int? limit}) {
    final now = DateTime.now();
    _cleanupExpiredBuckets(now);

    final bucket = _buckets[connectionId];
    if (bucket == null) {
      return [];
    }

    bucket.lastUpdatedAt = now;
    _trimBucket(bucket, now);

    final items = bucket.samples.toList(growable: false);
    if (limit == null || limit <= 0 || limit >= items.length) {
      return items;
    }

    return items.sublist(items.length - limit);
  }

  void clearConnection(String connectionId) {
    _buckets.remove(connectionId);
  }

  void _cleanupExpiredBuckets(DateTime now) {
    final expiredKeys = _buckets.entries
        .where((entry) => now.difference(entry.value.lastUpdatedAt) > retention)
        .map((entry) => entry.key)
        .toList(growable: false);

    for (final key in expiredKeys) {
      _buckets.remove(key);
    }
  }

  void _trimBucket(_MonitorHistoryBucket bucket, DateTime now) {
    while (bucket.samples.isNotEmpty &&
        now.millisecondsSinceEpoch - bucket.samples.first.timestamp >
            retention.inMilliseconds) {
      bucket.samples.removeFirst();
    }

    while (bucket.samples.length > maxSamplesPerConnection) {
      bucket.samples.removeFirst();
    }
  }
}
