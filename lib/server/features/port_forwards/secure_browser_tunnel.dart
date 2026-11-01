class SecureBrowserTunnel {
  final String id;
  final String profileId;
  final String connectionId;
  final String bindHost;
  final int bindPort;
  final int startedAt;

  const SecureBrowserTunnel({
    required this.id,
    required this.profileId,
    required this.connectionId,
    required this.bindHost,
    required this.bindPort,
    required this.startedAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'profileId': profileId,
    'connectionId': connectionId,
    'bindHost': bindHost,
    'bindPort': bindPort,
    'startedAt': startedAt,
    'status': 'running',
  };
}
