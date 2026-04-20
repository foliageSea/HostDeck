import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:dartssh2/dartssh2.dart';
import 'package:logging/logging.dart';

import '../models/managed_ssh_connection.dart';
import '../models/ssh_session.dart';

class SshSessionLimitExceeded implements Exception {
  final int maxSessions;

  const SshSessionLimitExceeded(this.maxSessions);

  @override
  String toString() => 'SSH session limit exceeded: $maxSessions';
}

class SshService {
  static const maxSessions = 8;
  static const _reconnectDelays = <Duration>[
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 10),
    Duration(seconds: 30),
  ];

  final _log = Logger('SshService');
  final Map<String, SshSession> _sessions = {};
  final Map<String, _ManagedConnectionState> _connections = {};
  final Map<String, String> _clientConnections = {};
  int _pendingSessionCreations = 0;

  Future<ManagedSshConnection> connect({
    required String clientId,
    required String host,
    required int port,
    required String username,
    String? password,
    String? privateKey,
  }) async {
    await disconnectClient(clientId);

    final connectionId = _generateId();
    final connection = _ManagedConnectionState(
      clientId: clientId,
      connectionId: connectionId,
      host: host,
      port: port,
      username: username,
      password: password,
      privateKey: privateKey,
    );

    _connections[connectionId] = connection;
    _clientConnections[clientId] = connectionId;
    _updateConnectionStatus(connection, 'connecting', lastError: null);

    try {
      final client = await _openClient(connection);
      _attachClient(connection, client);
      return connection.snapshot;
    } catch (e) {
      _updateConnectionStatus(connection, 'failed', lastError: e.toString());
      _clientConnections.remove(clientId);
      _connections.remove(connectionId);
      await connection.controller.close();
      rethrow;
    }
  }

  ManagedSshConnection? getConnectionById(String connectionId) {
    return _connections[connectionId]?.snapshot;
  }

  ManagedSshConnection? getConnectionForClient(String clientId) {
    final connectionId = _clientConnections[clientId];
    if (connectionId == null) {
      return null;
    }

    return getConnectionById(connectionId);
  }

  Stream<ManagedSshConnection>? watchConnection(String connectionId) {
    return _connections[connectionId]?.controller.stream;
  }

  SshSession? getSession(String id) => _sessions[id];

  SSHClient? getClient(String connectionId) => _connections[connectionId]?.client;

  Future<SshSession> createShell(String connectionId) async {
    final client = _requireOpenClient(connectionId);

    _reserveSessionCapacity();

    try {
      final shell = await client.shell(
        pty: SSHPtyConfig(width: 80, height: 24),
      );

      final sessionId = _generateId();
      final outputController = StreamController<String>.broadcast();

      shell.stdout.listen((data) {
        outputController.add(utf8.decode(data));
      });
      shell.stderr.listen((data) {
        outputController.add(utf8.decode(data));
      });

      final session = SshSession(
        id: sessionId,
        connectionId: connectionId,
        client: client,
        shell: shell,
        outputController: outputController,
      );

      _sessions[sessionId] = session;
      return session;
    } finally {
      _releaseSessionReservation();
    }
  }

  Future<SshSession> createSftpSession(String connectionId) async {
    final client = _requireOpenClient(connectionId);

    _reserveSessionCapacity();

    try {
      final sessionId = _generateId();
      final session = SshSession(
        id: sessionId,
        connectionId: connectionId,
        client: client,
        shell: null,
      );

      _sessions[sessionId] = session;
      return session;
    } finally {
      _releaseSessionReservation();
    }
  }

  Map<String, dynamic> getRuntimeSnapshot() {
    final sessionCounts = <String, int>{};
    for (final session in _sessions.values) {
      sessionCounts.update(
        session.connectionId,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }

    final clients =
        _connections.values
            .map(
              (connection) => {
                'clientId': connection.clientId,
                'connectionId': connection.connectionId,
                'status': connection.status,
                'isClosed': connection.client?.isClosed ?? true,
                'sessionCount': sessionCounts[connection.connectionId] ?? 0,
              },
            )
            .toList()
          ..sort(
            (left, right) => (left['connectionId'] as String).compareTo(
              right['connectionId'] as String,
            ),
          );

    final sessions =
        _sessions.values
            .map(
              (session) => {
                'sessionId': session.id,
                'connectionId': session.connectionId,
                'type': session.shell == null ? 'sftp' : 'shell',
                'hasShell': session.shell != null,
                'clientClosed': session.client.isClosed,
              },
            )
            .toList()
          ..sort(
            (left, right) => (left['sessionId'] as String).compareTo(
              right['sessionId'] as String,
            ),
          );

    return {
      'totalClients': clients.length,
      'totalSessions': sessions.length,
      'clients': clients,
      'sessions': sessions,
    };
  }

  Future<void> closeSession(String id) async {
    final session = _sessions[id];
    if (session != null) {
      await session.close();
      _sessions.remove(id);
    }
  }

  Future<void> disconnect(String connectionId) async {
    final connection = _connections[connectionId];
    if (connection == null) {
      return;
    }

    await _disconnectManagedConnection(connection, removeMapping: true);
  }

  Future<void> disconnectClient(String clientId) async {
    final connectionId = _clientConnections[clientId];
    if (connectionId == null) {
      return;
    }

    await disconnect(connectionId);
  }

  void _reserveSessionCapacity() {
    if (_sessions.length + _pendingSessionCreations >= maxSessions) {
      throw const SshSessionLimitExceeded(maxSessions);
    }

    _pendingSessionCreations++;
  }

  void _releaseSessionReservation() {
    if (_pendingSessionCreations > 0) {
      _pendingSessionCreations--;
    }
  }

  SSHClient _requireOpenClient(String connectionId) {
    final connection = _connections[connectionId];
    if (connection == null) {
      throw Exception('Connection not found: $connectionId');
    }

    final client = connection.client;
    if (client == null) {
      throw Exception('Connection is not ready');
    }

    if (client.isClosed) {
      throw Exception('Connection is closed');
    }

    return client;
  }

  Future<SSHClient> _openClient(_ManagedConnectionState connection) async {
    final socket = await SSHSocket.connect(connection.host, connection.port);

    final client = SSHClient(
      socket,
      username: connection.username,
      onPasswordRequest:
          connection.password != null ? () => connection.password! : null,
      identities: connection.privateKey != null &&
              connection.privateKey!.trim().isNotEmpty
          ? [...SSHKeyPair.fromPem(connection.privateKey!)]
          : [],
    );

    await client.authenticated;
    return client;
  }

  void _attachClient(_ManagedConnectionState connection, SSHClient client) {
    connection.client = client;
    connection.reconnectTimer?.cancel();
    connection.reconnectTimer = null;
    connection.reconnectAttempts = 0;
    _updateConnectionStatus(connection, 'connected', lastError: null);

    unawaited(
      client.done.then((_) {
        _handleClientDone(connection.connectionId, 'SSH connection closed');
      }).catchError((error) {
        _handleClientDone(connection.connectionId, error.toString());
      }),
    );
  }

  void _handleClientDone(String connectionId, String error) {
    final connection = _connections[connectionId];
    if (connection == null || connection.isDisconnecting) {
      return;
    }

    connection.client = null;
    _closeSessionsForConnection(connectionId);
    _scheduleReconnect(connection, error);
  }

  void _scheduleReconnect(_ManagedConnectionState connection, String error) {
    if (!_clientConnections.containsKey(connection.clientId)) {
      return;
    }

    connection.reconnectTimer?.cancel();
    final attempt = connection.reconnectAttempts;
    final delay = _reconnectDelays[min(attempt, _reconnectDelays.length - 1)];
    connection.reconnectAttempts = attempt + 1;
    _updateConnectionStatus(connection, 'reconnecting', lastError: error);

    connection.reconnectTimer = Timer(delay, () async {
      if (!_clientConnections.containsKey(connection.clientId) ||
          connection.isDisconnecting) {
        return;
      }

      try {
        final client = await _openClient(connection);
        _attachClient(connection, client);
      } catch (e, stackTrace) {
        _log.warning(
          'Reconnect failed for ${connection.connectionId}',
          e,
          stackTrace,
        );
        _scheduleReconnect(connection, e.toString());
      }
    });
  }

  Future<void> _disconnectManagedConnection(
    _ManagedConnectionState connection, {
    required bool removeMapping,
  }) async {
    connection.isDisconnecting = true;
    connection.reconnectTimer?.cancel();
    connection.reconnectTimer = null;

    final client = connection.client;
    connection.client = null;

    _closeSessionsForConnection(connection.connectionId);

    if (client != null && !client.isClosed) {
      client.close();
    }

    _updateConnectionStatus(connection, 'disconnected', lastError: null);

    if (removeMapping) {
      _clientConnections.remove(connection.clientId);
      _connections.remove(connection.connectionId);
      await connection.controller.close();
    }
  }

  void _closeSessionsForConnection(String connectionId) {
    final sessionsToRemove = _sessions.values
        .where((session) => session.connectionId == connectionId)
        .toList();

    for (final session in sessionsToRemove) {
      unawaited(session.close());
      _sessions.remove(session.id);
    }
  }

  void _updateConnectionStatus(
    _ManagedConnectionState connection,
    String status, {
    required String? lastError,
  }) {
    connection.status = status;
    connection.lastError = lastError;
    connection.updatedAt = DateTime.now();

    if (!connection.controller.isClosed) {
      connection.controller.add(connection.snapshot);
    }
  }

  String _generateId() {
    return DateTime.now().millisecondsSinceEpoch.toString() +
        Random().nextInt(1000).toString();
  }
}

class _ManagedConnectionState {
  final String clientId;
  final String connectionId;
  final String host;
  final int port;
  final String username;
  final String? password;
  final String? privateKey;
  final StreamController<ManagedSshConnection> controller =
      StreamController<ManagedSshConnection>.broadcast();

  SSHClient? client;
  Timer? reconnectTimer;
  int reconnectAttempts = 0;
  bool isDisconnecting = false;
  String status = 'disconnected';
  String? lastError;
  DateTime updatedAt = DateTime.now();

  _ManagedConnectionState({
    required this.clientId,
    required this.connectionId,
    required this.host,
    required this.port,
    required this.username,
    required this.password,
    required this.privateKey,
  });

  ManagedSshConnection get snapshot {
    final normalizedStatus = status;
    return ManagedSshConnection(
      clientId: clientId,
      connectionId: connectionId,
      host: host,
      port: port,
      username: username,
      password: password,
      privateKey: privateKey,
      status: normalizedStatus,
      isConnected: normalizedStatus == 'connected',
      isRecoverable:
          normalizedStatus == 'connected' || normalizedStatus == 'reconnecting',
      lastError: lastError,
      updatedAt: updatedAt,
    );
  }
}
