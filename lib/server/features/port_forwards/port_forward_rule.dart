class PortForwardRule {
  final int? id;
  final String name;
  final bool enabled;
  final String bindHost;
  final int localPort;
  final String remoteHost;
  final int remotePort;
  final int? createdAt;
  final int? updatedAt;

  const PortForwardRule({
    this.id,
    required this.name,
    required this.enabled,
    required this.bindHost,
    required this.localPort,
    required this.remoteHost,
    required this.remotePort,
    this.createdAt,
    this.updatedAt,
  });

  factory PortForwardRule.fromJson(Map<String, dynamic> json) {
    return PortForwardRule(
      id: json['id'] == null ? null : int.tryParse(json['id'].toString()),
      name: (json['name'] ?? '').toString().trim(),
      enabled: json['enabled'] == true || json['enabled'] == 1,
      bindHost: (json['bindHost'] ?? '127.0.0.1').toString().trim(),
      localPort: int.parse(json['localPort'].toString()),
      remoteHost: (json['remoteHost'] ?? '127.0.0.1').toString().trim(),
      remotePort: int.parse(json['remotePort'].toString()),
      createdAt: json['createdAt'] == null
          ? null
          : int.tryParse(json['createdAt'].toString()),
      updatedAt: json['updatedAt'] == null
          ? null
          : int.tryParse(json['updatedAt'].toString()),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'enabled': enabled,
    'bindHost': bindHost,
    'localPort': localPort,
    'remoteHost': remoteHost,
    'remotePort': remotePort,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
  };

  PortForwardRule copyWith({
    int? id,
    String? name,
    bool? enabled,
    String? bindHost,
    int? localPort,
    String? remoteHost,
    int? remotePort,
    int? createdAt,
    int? updatedAt,
  }) {
    return PortForwardRule(
      id: id ?? this.id,
      name: name ?? this.name,
      enabled: enabled ?? this.enabled,
      bindHost: bindHost ?? this.bindHost,
      localPort: localPort ?? this.localPort,
      remoteHost: remoteHost ?? this.remoteHost,
      remotePort: remotePort ?? this.remotePort,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
