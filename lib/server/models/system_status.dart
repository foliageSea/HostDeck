class SystemStatus {
  final String cpu;
  final RamStatus ram;
  final String disk;

  SystemStatus({required this.cpu, required this.ram, required this.disk});

  Map<String, dynamic> toJson() => {
    'cpu': cpu,
    'ram': ram.toJson(),
    'disk': disk,
  };
}

class RamStatus {
  final int total;
  final int used;

  RamStatus({required this.total, required this.used});

  Map<String, dynamic> toJson() => {
    'total': total,
    'used': used,
  };
}
