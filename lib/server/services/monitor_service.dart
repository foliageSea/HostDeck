import '../repositories/ssh_repository.dart';
import '../models/ssh_session.dart';
import '../models/system_status.dart';

class _NetworkSnapshot {
  final int rxBytes;
  final int txBytes;
  final DateTime timestamp;

  _NetworkSnapshot(this.rxBytes, this.txBytes, this.timestamp);
}

class MonitorService {
  final SshRepository _repository;
  final Map<String, _NetworkSnapshot> _lastNetworkStats = {};

  MonitorService(this._repository);

  void clearSession(String sessionId) {
    _lastNetworkStats.remove(sessionId);
  }

  Future<SystemStatus> getSystemStatus(SshSession session) async {
    // Keep monitor commands sequential to avoid exhausting low SSH MaxSessions.
    final ramResult = await _repository.exec(session, 'free -m | grep Mem');
    final diskResult = await _repository.exec(
      session,
      "df -h / | awk 'NR==2 {print \$5}'",
    );
    final uptimeResult = await _repository.exec(session, "uptime");
    final topResult = await _repository
        .exec(
          session,
          "LC_ALL=C top -bn1 2>/dev/null | grep -E 'Cpu\\(s\\)|CPU:' || LC_ALL=C top -n1 2>/dev/null | grep -E 'Cpu\\(s\\)|CPU:' || true",
        )
        .catchError((_) => "");
    final netResult = await _repository
        .exec(session, "cat /proc/net/dev")
        .catchError((_) => "");

    final results = [ramResult, diskResult, uptimeResult, topResult, netResult];

    // Parse RAM
    // Mem: 7963 3855 ...
    final ramParts = results[0].trim().split(RegExp(r'\s+'));
    final totalRam = ramParts.length > 1 ? (int.tryParse(ramParts[1]) ?? 0) : 0;
    final usedRam = ramParts.length > 2 ? (int.tryParse(ramParts[2]) ?? 0) : 0;

    final diskUsage = results[1].trim();

    // Parse load average from uptime: " 13:22:01 up 1 day,  3:10,  1 user,  load average: 0.00, 0.00, 0.00"
    final uptimeStr = results[2].trim();
    final loadIndex = uptimeStr.indexOf('load average:');
    String loadAvg = '0.0';
    if (loadIndex != -1) {
      final loads = uptimeStr.substring(loadIndex + 13).split(',');
      if (loads.isNotEmpty) {
        loadAvg = loads[0].trim();
      }
    }

    // Parse CPU usage from top: "%Cpu(s):  0.3 us,  0.3 sy,  0.0 ni, 99.3 id,  0.0 wa,  0.0 hi,  0.0 si,  0.0 st"
    // Also handle: "CPU:   0% usr   0% sys   0% nic 100% idle   0% io   0% irq   0% sirq" (BusyBox)
    double? cpuUsage;
    try {
      var topStr = results[3].trim();
      if (topStr.isNotEmpty) {
        // Remove ANSI escape codes
        topStr = topStr.replaceAll(RegExp(r'\x1B\[[0-?]*[ -/]*[@-~]'), '');

        // Regex to match idle percentage:
        // 1. "99.3 id" (Standard top)
        // 2. "99.3% id"
        // 3. "100% idle" (BusyBox)
        // Also supports comma decimal separator just in case LC_ALL=C fails
        final idleRegExp = RegExp(
          r'(\d+(?:[\.,]\d+)?)\s*%?\s*(?:id|idle)',
          caseSensitive: false,
        );
        final match = idleRegExp.firstMatch(topStr);
        if (match != null) {
          var idleStr = match.group(1);
          if (idleStr != null) {
            idleStr = idleStr.replaceAll(',', '.');
            final idle = double.tryParse(idleStr);
            if (idle != null) {
              cpuUsage = 100.0 - idle;
            }
          }
        }
      }
    } catch (e) {
      // Ignore parsing errors
    }

    // Parse Network Usage
    NetworkStatus? networkStatus;
    try {
      final netStr = results[4];
      if (netStr.isNotEmpty) {
        final lines = netStr.trim().split('\n');
        int currentRx = 0;
        int currentTx = 0;

        // Skip header lines (usually first 2 lines)
        for (var i = 2; i < lines.length; i++) {
          var line = lines[i].trim();
          if (line.isEmpty) continue;

          // Handle "eth0:123" by ensuring space after colon
          line = line.replaceAll(':', ' ');
          final tokens = line.trim().split(RegExp(r'\s+'));

          if (tokens.length < 17) continue; // Interface name + 16 stats columns

          final iface = tokens[0];
          if (iface == 'lo') continue; // Skip loopback

          final rx = int.tryParse(tokens[1]) ?? 0;
          final tx = int.tryParse(tokens[9]) ?? 0;

          currentRx += rx;
          currentTx += tx;
        }

        final now = DateTime.now();
        final lastSnapshot = _lastNetworkStats[session.id];

        double downloadSpeed = 0.0;
        double uploadSpeed = 0.0;

        if (lastSnapshot != null) {
          final duration =
              now.difference(lastSnapshot.timestamp).inMilliseconds / 1000.0;
          if (duration > 0) {
            // Handle overflow/reset check (simple check: if current < last, ignore or assume 0)
            if (currentRx >= lastSnapshot.rxBytes) {
              downloadSpeed = (currentRx - lastSnapshot.rxBytes) / duration;
            }
            if (currentTx >= lastSnapshot.txBytes) {
              uploadSpeed = (currentTx - lastSnapshot.txBytes) / duration;
            }
          }
        }

        _lastNetworkStats[session.id] = _NetworkSnapshot(
          currentRx,
          currentTx,
          now,
        );

        networkStatus = NetworkStatus(
          uploadSpeed: uploadSpeed,
          downloadSpeed: downloadSpeed,
        );
      }
    } catch (e) {
      // Ignore network parsing errors
    }

    return SystemStatus(
      timestamp: DateTime.now().millisecondsSinceEpoch,
      cpu: loadAvg,
      cpuUsage: cpuUsage ?? 0.0,
      ram: RamStatus(total: totalRam, used: usedRam),
      disk: diskUsage,
      network: networkStatus,
    );
  }
}
