class DockerVolume {
  final String name;
  final String driver;
  final String scope;
  final String mountpoint;
  final DateTime? createdAt;
  final int refCount;

  DockerVolume({
    required this.name,
    required this.driver,
    required this.scope,
    required this.mountpoint,
    this.createdAt,
    this.refCount = 0,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'driver': driver,
    'scope': scope,
    'mountpoint': mountpoint,
    'createdAt': createdAt?.toIso8601String(),
    'refCount': refCount,
  };

  factory DockerVolume.fromJson(Map<String, dynamic> json) {
    return DockerVolume(
      name: json['name'] as String? ?? '',
      driver: json['driver'] as String? ?? '',
      scope: json['scope'] as String? ?? '',
      mountpoint: json['mountpoint'] as String? ?? '',
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String)
          : null,
      refCount: json['refCount'] as int? ?? 0,
    );
  }
}
