import '../repositories/ssh_repository.dart';
import '../models/ssh_session.dart';
import '../models/system_status.dart';

class MonitorService {
  final SshRepository _repository;

  MonitorService(this._repository);

  Future<SystemStatus> getSystemStatus(SshSession session) async {
    // Basic Linux commands for monitoring
    final ramFuture = _repository.exec(session, 'free -m | grep Mem');
    // disk usage of /
    final diskFuture = _repository.exec(session, "df -h / | awk 'NR==2 {print \$5}'"); 
    // Load average from uptime
    final uptimeFuture = _repository.exec(session, "uptime");
    // CPU usage from top (batch mode, 1 iteration)
    final topFuture = _repository.exec(session, "LC_ALL=C top -bn1 | grep 'Cpu(s)' || true")
        .catchError((_) => "");

    final results = await Future.wait([ramFuture, diskFuture, uptimeFuture, topFuture]);
    
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
    double? cpuUsage;
    try {
      final topStr = results[3].trim();
      if (topStr.isNotEmpty) {
        // Find "id" (idle) value
        // Split by comma first
        final parts = topStr.split(',');
        for (var part in parts) {
          if (part.trim().endsWith('id')) {
             // extract number " 99.3 id"
             final valStr = part.trim().split(' ')[0];
             final idle = double.tryParse(valStr);
             if (idle != null) {
               cpuUsage = 100.0 - idle;
             }
             break;
          }
        }
      }
    } catch (e) {
      // Ignore parsing errors
    }

    return SystemStatus(
      cpu: loadAvg,
      cpuUsage: cpuUsage,
      ram: RamStatus(total: totalRam, used: usedRam),
      disk: diskUsage,
    );
  }
}
