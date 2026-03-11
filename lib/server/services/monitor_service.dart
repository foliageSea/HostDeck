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

    final results = await Future.wait([ramFuture, diskFuture, uptimeFuture]);
    
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

    return SystemStatus(
      cpu: loadAvg,
      ram: RamStatus(total: totalRam, used: usedRam),
      disk: diskUsage,
    );
  }
}
