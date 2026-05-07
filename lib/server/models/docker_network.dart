class DockerNetwork {
  final String id;
  final String name;
  final String driver;
  final String scope;
  final DateTime? createdAt;
  final bool internal;
  final bool attachable;
  final bool ingress;
  final int connectedContainers;
  final List<String> connectedContainerNames;

  DockerNetwork({
    required this.id,
    required this.name,
    required this.driver,
    required this.scope,
    this.createdAt,
    this.internal = false,
    this.attachable = false,
    this.ingress = false,
    this.connectedContainers = 0,
    this.connectedContainerNames = const [],
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'driver': driver,
    'scope': scope,
    'createdAt': createdAt?.toIso8601String(),
    'internal': internal,
    'attachable': attachable,
    'ingress': ingress,
    'connectedContainers': connectedContainers,
    'connectedContainerNames': connectedContainerNames,
  };

  factory DockerNetwork.fromJson(Map<String, dynamic> json) {
    return DockerNetwork(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      driver: json['driver'] as String? ?? '',
      scope: json['scope'] as String? ?? '',
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String)
          : null,
      internal: json['internal'] as bool? ?? false,
      attachable: json['attachable'] as bool? ?? false,
      ingress: json['ingress'] as bool? ?? false,
      connectedContainers: json['connectedContainers'] as int? ?? 0,
      connectedContainerNames:
          (json['connectedContainerNames'] as List?)?.cast<String>() ?? [],
    );
  }
}
