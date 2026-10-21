class SystemStatus {
  final int timestamp;
  final String cpu;
  final double? cpuUsage;
  final RamStatus ram;
  final String disk;
  final List<DiskStatus> disks;
  final NetworkStatus? network;
  final SystemInfo? systemInfo;

  SystemStatus({
    required this.timestamp,
    required this.cpu,
    this.cpuUsage,
    required this.ram,
    required this.disk,
    this.disks = const [],
    this.network,
    this.systemInfo,
  });

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp,
    'cpu': cpu,
    'cpuUsage': cpuUsage,
    'ram': ram.toJson(),
    'disk': disk,
    if (disks.isNotEmpty) 'disks': disks.map((disk) => disk.toJson()).toList(),
    if (network != null) 'network': network!.toJson(),
    if (systemInfo != null) 'systemInfo': systemInfo!.toJson(),
  };
}

class DiskStatus {
  final String filesystem;
  final String mountpoint;
  final int total;
  final int used;
  final int available;
  final double usagePercent;

  DiskStatus({
    required this.filesystem,
    required this.mountpoint,
    required this.total,
    required this.used,
    required this.available,
    required this.usagePercent,
  });

  Map<String, dynamic> toJson() => {
    'filesystem': filesystem,
    'mountpoint': mountpoint,
    'total': total,
    'used': used,
    'available': available,
    'usagePercent': usagePercent,
  };
}

class SystemInfo {
  final String hostname;
  final String distribution;
  final String kernel;
  final String architecture;
  final String hostAddress;
  final String bootTime;
  final String uptime;
  final int? uptimeSeconds;

  SystemInfo({
    required this.hostname,
    required this.distribution,
    required this.kernel,
    required this.architecture,
    required this.hostAddress,
    required this.bootTime,
    required this.uptime,
    this.uptimeSeconds,
  });

  Map<String, dynamic> toJson() => {
    'hostname': hostname,
    'distribution': distribution,
    'kernel': kernel,
    'architecture': architecture,
    'hostAddress': hostAddress,
    'bootTime': bootTime,
    'uptime': uptime,
    if (uptimeSeconds != null) 'uptimeSeconds': uptimeSeconds,
  };
}

class RamStatus {
  final int total;
  final int used;

  RamStatus({required this.total, required this.used});

  Map<String, dynamic> toJson() => {'total': total, 'used': used};
}

class NetworkStatus {
  final double uploadSpeed; // bytes per second
  final double downloadSpeed; // bytes per second

  NetworkStatus({required this.uploadSpeed, required this.downloadSpeed});

  Map<String, dynamic> toJson() => {
    'uploadSpeed': uploadSpeed,
    'downloadSpeed': downloadSpeed,
  };
}
