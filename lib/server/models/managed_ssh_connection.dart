class ManagedSshConnection {
  final String clientId;
  final String connectionId;
  final String host;
  final int port;
  final String username;
  final String? password;
  final String? privateKey;
  final String status;
  final bool isConnected;
  final bool isRecoverable;
  final String? lastError;
  final DateTime updatedAt;

  const ManagedSshConnection({
    required this.clientId,
    required this.connectionId,
    required this.host,
    required this.port,
    required this.username,
    required this.password,
    required this.privateKey,
    required this.status,
    required this.isConnected,
    required this.isRecoverable,
    required this.lastError,
    required this.updatedAt,
  });

  Map<String, dynamic> toClientJson() {
    return {
      'connectionId': connectionId,
      'host': host,
      'port': port,
      'username': username,
      'status': status,
      'isConnected': isConnected,
      'isRecoverable': isRecoverable,
      'lastError': lastError,
      'updatedAt': updatedAt.toIso8601String(),
    };
  }
}
