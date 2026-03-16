class ServerConfig {
  final int? id;
  final String name;
  final String host;
  final int port;
  final String username;
  final String? password;
  final String? privateKey;
  final int? createdAt;

  ServerConfig({
    this.id,
    required this.name,
    required this.host,
    required this.port,
    required this.username,
    this.password,
    this.privateKey,
    this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'host': host,
      'port': port,
      'username': username,
      'password': password,
      'privateKey': privateKey,
      'createdAt': createdAt,
    };
  }

  factory ServerConfig.fromJson(Map<String, dynamic> json) {
    return ServerConfig(
      id: json['id'] as int?,
      name: json['name'] as String? ?? '',
      host: json['host'] as String? ?? '',
      port: json['port'] is int ? json['port'] : int.tryParse(json['port']?.toString() ?? '22') ?? 22,
      username: json['username'] as String? ?? '',
      password: json['password'] as String?,
      privateKey: json['privateKey'] as String?,
      createdAt: json['createdAt'] as int?,
    );
  }
}
