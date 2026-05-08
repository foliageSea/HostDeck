class DockerContainer {
  final String id;
  final String name;
  final String image;
  final String status;
  final String state;
  final List<String> ports;
  final List<DockerContainerNetwork> networks;
  final DateTime? createdAt;

  DockerContainer({
    required this.id,
    required this.name,
    required this.image,
    required this.status,
    required this.state,
    this.ports = const [],
    this.networks = const [],
    this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'image': image,
    'status': status,
    'state': state,
    'ports': ports,
    'networks': networks.map((item) => item.toJson()).toList(),
    'createdAt': createdAt?.toIso8601String(),
  };

  factory DockerContainer.fromJson(Map<String, dynamic> json) {
    return DockerContainer(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      image: json['image'] as String? ?? '',
      status: json['status'] as String? ?? '',
      state: json['state'] as String? ?? '',
      ports: (json['ports'] as List?)?.cast<String>() ?? [],
      networks:
          (json['networks'] as List?)
              ?.whereType<Map>()
              .map(
                (item) => DockerContainerNetwork.fromJson(
                  Map<String, dynamic>.from(item),
                ),
              )
              .toList() ??
          const [],
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String)
          : null,
    );
  }
}

class DockerContainerNetwork {
  final String name;
  final String ipAddress;

  DockerContainerNetwork({required this.name, required this.ipAddress});

  Map<String, dynamic> toJson() => {'name': name, 'ipAddress': ipAddress};

  factory DockerContainerNetwork.fromJson(Map<String, dynamic> json) {
    return DockerContainerNetwork(
      name: json['name'] as String? ?? '',
      ipAddress: json['ipAddress'] as String? ?? '',
    );
  }
}
