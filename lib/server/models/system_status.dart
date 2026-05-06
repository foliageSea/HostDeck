class SystemStatus {
  final int timestamp;
  final String cpu;
  final double? cpuUsage;
  final RamStatus ram;
  final String disk;
  final NetworkStatus? network;

  SystemStatus({
    required this.timestamp,
    required this.cpu,
    this.cpuUsage,
    required this.ram,
    required this.disk,
    this.network,
  });

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp,
    'cpu': cpu,
    'cpuUsage': cpuUsage,
    'ram': ram.toJson(),
    'disk': disk,
    if (network != null) 'network': network!.toJson(),
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
