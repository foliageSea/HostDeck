class DockerVolume {
  final String name;
  final String driver;
  final String scope;
  final String mountpoint;
  final DateTime? createdAt;
  final int refCount;
  final List<String> usedBy;

  DockerVolume({
    required this.name,
    required this.driver,
    required this.scope,
    required this.mountpoint,
    this.createdAt,
    this.refCount = 0,
    this.usedBy = const [],
  });

  DockerVolume copyWith({int? refCount, List<String>? usedBy}) => DockerVolume(
    name: name,
    driver: driver,
    scope: scope,
    mountpoint: mountpoint,
    createdAt: createdAt,
    refCount: refCount ?? this.refCount,
    usedBy: usedBy ?? this.usedBy,
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'driver': driver,
    'scope': scope,
    'mountpoint': mountpoint,
    'createdAt': createdAt?.toIso8601String(),
    'refCount': refCount,
    'usedBy': usedBy,
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
      usedBy:
          (json['usedBy'] as List?)?.map((item) => item.toString()).toList() ??
          const [],
    );
  }
}
