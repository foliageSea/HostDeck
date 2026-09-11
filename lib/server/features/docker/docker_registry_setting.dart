class DockerRegistrySetting {
  final int? id;
  final String targetKey;
  final String address;
  final String name;
  final String namespace;
  final bool authentication;
  final String username;

  const DockerRegistrySetting({
    this.id,
    required this.targetKey,
    required this.address,
    required this.name,
    required this.namespace,
    required this.authentication,
    required this.username,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'address': address,
    'name': name,
    'namespace': namespace,
    'authentication': authentication,
    'username': username,
  };
}
