import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:dartssh2/dartssh2.dart';
import 'package:logging/logging.dart';
import 'package:host_deck/server/core/ssh/ssh_connection_handle.dart';
import 'package:host_deck/server/core/ssh/ssh_operation_limiter.dart';
import 'package:host_deck/server/core/ssh/ssh_session.dart';

typedef SshSocketConnector = Future<SSHSocket> Function(String host, int port);
typedef SshClientFactory =
    SSHClient Function(
      SSHSocket socket, {
      required String username,
      String? password,
      String? privateKey,
    });

class SshSessionLimitExceeded implements Exception {
  final int maxSessions;

  const SshSessionLimitExceeded(this.maxSessions);

  @override
  String toString() => 'SSH session limit exceeded: $maxSessions';
}

enum SshSessionPurpose {
  terminal,
  fileManagement,
  fileTask,
  docker,
  dockerCompose,
  containerShell,
  systemMonitor,
  agent,
  cronTask,
  processManagement,
  aiAgent,
}

class SshConnectionMetadata {
  final String host;
  final int port;
  final String username;
  final int? serverId;

  const SshConnectionMetadata({
    required this.host,
    required this.port,
    required this.username,
    this.serverId,
  });

  String get targetKey =>
      serverId == null ? '$username@$host:$port' : 'server:$serverId';
}

class SshService {
  static const maxSessions = 8;
  static const maxConcurrentOperations = 4;

  final Map<String, SshSession> _sessions = {};
  final Map<String, Set<SshSessionPurpose>> _sessionPurposes = {};
  final Map<String, SSHClient> _clients = {};
  final Map<String, int?> _connectionServerIds = {};
  final Map<String, SshConnectionMetadata> _connectionMetadata = {};
  final Map<String, SshOperationLimiter> _operationLimiters = {};
  final List<FutureOr<void> Function(String connectionId)>
  _disconnectListeners = [];
  final Map<String, int> _pendingSessionCreations = {};
  final SshSocketConnector _socketConnector;
  final SshClientFactory _clientFactory;

  final logger = Logger('SshService');

  SshService({
    SshSocketConnector socketConnector = SSHSocket.connect,
    SshClientFactory clientFactory = _createClient,
  }) : _socketConnector = socketConnector,
       _clientFactory = clientFactory;

  static SSHClient _createClient(
    SSHSocket socket, {
    required String username,
    String? password,
    String? privateKey,
  }) {
    return SSHClient(
      socket,
      username: username,
      onPasswordRequest: password != null ? () => password : null,
      identities: privateKey != null && privateKey.trim().isNotEmpty
          ? [...SSHKeyPair.fromPem(privateKey)]
          : [],
    );
  }

  Future<String> connect({
    required String host,
    required int port,
    required String username,
    int? serverId,
    String? password,
    String? privateKey,
  }) async {
    final socket = await _socketConnector(host, port);
    final client = _clientFactory(
      socket,
      username: username,
      password: password,
      privateKey: privateKey,
    );

    try {
      await client.authenticated;
    } catch (_) {
      client.close();
      rethrow;
    }

    final connectionId = _generateId();
    _clients[connectionId] = client;
    _connectionServerIds[connectionId] = serverId;
    _connectionMetadata[connectionId] = SshConnectionMetadata(
      host: host,
      port: port,
      username: username,
      serverId: serverId,
    );
    _operationLimiters[connectionId] = SshOperationLimiter(
      maxConcurrentOperations: maxConcurrentOperations,
    );

    // Handle unexpected disconnection, including futures completed with errors.
    unawaited(
      client.done
          .whenComplete(() {
            logger.warning('Connection $connectionId closed');
            _disconnectInternal(connectionId);
          })
          .catchError(
            (error) =>
                logger.severe('Error $error on connection $connectionId'),
          ),
    );

    return connectionId;
  }

  int? getServerId(String connectionId) => _connectionServerIds[connectionId];

  SshConnectionMetadata? getConnectionMetadata(String connectionId) =>
      _connectionMetadata[connectionId];

  Future<SshSession> createShell(
    String connectionId, {
    required SshSessionPurpose purpose,
  }) async {
    final client = _clients[connectionId];
    if (client == null) {
      throw Exception('Connection not found: $connectionId');
    }

    if (client.isClosed) {
      _disconnectInternal(connectionId);
      throw Exception('Connection is closed');
    }

    _reserveSessionCapacity(connectionId);

    try {
      final shell = await _operationLimiterFor(
        connectionId,
      ).run(() => client.shell(pty: SSHPtyConfig(width: 80, height: 24)));

      final sessionId = _generateId();
      final outputController = StreamController<String>.broadcast();

      // Pipe shell output to controller
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
        operationLimiter: _operationLimiterFor(connectionId),
        shell: shell,
        outputController: outputController,
      );

      _sessions[sessionId] = session;
      _sessionPurposes[sessionId] = {purpose};

      // Handle client disconnection (only once per client usually, but safe to add listener?)
      // Actually client.done is a future. We should set it up when client is created.
      // But we didn't do it in connect() fully.
      // Let's do it here? No, better in connect.
      // However, if we do it in connect, we need to know how to clean up.

      return session;
    } finally {
      _releaseSessionReservation(connectionId);
    }
  }

  Future<SshSession> createSftpSession(
    String connectionId, {
    required SshSessionPurpose purpose,
  }) async {
    final client = _clients[connectionId];
    if (client == null) {
      throw Exception('Connection not found: $connectionId');
    }

    if (client.isClosed) {
      _disconnectInternal(connectionId);
      throw Exception('Connection is closed');
    }

    _reserveSessionCapacity(connectionId);

    try {
      final sessionId = _generateId();
      // Create session without shell
      final session = SshSession(
        id: sessionId,
        connectionId: connectionId,
        client: client,
        operationLimiter: _operationLimiterFor(connectionId),
        shell: null,
      );

      _sessions[sessionId] = session;
      _sessionPurposes[sessionId] = {purpose};
      return session;
    } finally {
      _releaseSessionReservation(connectionId);
    }
  }

  // Helper to setup client cleanup.
  // Since we modified connect to return SshSession via createShell,
  // we need to attach the listener in connect or right after client creation.
  // But wait, connect calls createShell.

  // Let's fix connect() to attach listener.

  SshSession? getSession(String id) => _sessions[id];

  bool addSessionPurpose(String id, SshSessionPurpose purpose) {
    if (!_sessions.containsKey(id)) {
      return false;
    }

    _sessionPurposes.putIfAbsent(id, () => {}).add(purpose);
    return true;
  }

  SSHClient? getClient(String connectionId) => _clients[connectionId];

  SshConnectionHandle? getConnectionHandle(String connectionId) {
    final client = _clients[connectionId];
    final operationLimiter = _operationLimiters[connectionId];
    if (client == null || operationLimiter == null) {
      return null;
    }
    if (client.isClosed) {
      _disconnectInternal(connectionId);
      return null;
    }
    return SshConnectionHandle(
      connectionId: connectionId,
      client: client,
      operationLimiter: operationLimiter,
    );
  }

  void addDisconnectListener(
    FutureOr<void> Function(String connectionId) listener,
  ) {
    _disconnectListeners.add(listener);
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
        _clients.entries.map((entry) {
          final metadata = _connectionMetadata[entry.key];
          return {
            'connectionId': entry.key,
            'username': metadata?.username,
            'host': metadata?.host,
            'port': metadata?.port,
            'isClosed': entry.value.isClosed,
            'sessionCount': sessionCounts[entry.key] ?? 0,
            ...?_operationLimiters[entry.key]?.snapshot(),
          };
        }).toList()..sort(
          (left, right) => (left['connectionId'] as String).compareTo(
            right['connectionId'] as String,
          ),
        );

    final sessions =
        _sessions.values.map((session) {
          final purposes =
              (_sessionPurposes[session.id] ?? const <SshSessionPurpose>{})
                  .map((purpose) => purpose.name)
                  .toList()
                ..sort();
          return {
            'sessionId': session.id,
            'connectionId': session.connectionId,
            'type': session.shell == null ? 'sftp' : 'shell',
            'purposes': purposes,
            'hasShell': session.shell != null,
            'clientClosed': session.client.isClosed,
          };
        }).toList()..sort(
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
      _sessionPurposes.remove(id);
    }
  }

  Future<void> disconnect(String connectionId) async {
    final client = _clients[connectionId];
    if (client != null) {
      client.close();
      _disconnectInternal(connectionId);
    }
  }

  void _reserveSessionCapacity(String connectionId) {
    final sessionCount = _sessions.values
        .where((session) => session.connectionId == connectionId)
        .length;
    final pendingCount = _pendingSessionCreations[connectionId] ?? 0;
    if (sessionCount + pendingCount >= maxSessions) {
      throw const SshSessionLimitExceeded(maxSessions);
    }

    _pendingSessionCreations[connectionId] = pendingCount + 1;
  }

  void _releaseSessionReservation(String connectionId) {
    final pendingCount = _pendingSessionCreations[connectionId] ?? 0;
    if (pendingCount <= 1) {
      _pendingSessionCreations.remove(connectionId);
    } else {
      _pendingSessionCreations[connectionId] = pendingCount - 1;
    }
  }

  void _disconnectInternal(String connectionId) {
    final client = _clients.remove(connectionId);
    if (client == null) {
      return;
    }

    final sessionsToRemove = _sessions.values
        .where((s) => s.connectionId == connectionId)
        .toList();
    for (final session in sessionsToRemove) {
      // We don't await here because this might be called from sync context or fire-and-forget
      session.close();
      _sessions.remove(session.id);
      _sessionPurposes.remove(session.id);
    }
    _connectionServerIds.remove(connectionId);
    _connectionMetadata.remove(connectionId);
    _operationLimiters.remove(connectionId);
    for (final listener in _disconnectListeners) {
      unawaited(Future.sync(() => listener(connectionId)));
    }
  }

  SshOperationLimiter _operationLimiterFor(String connectionId) {
    return _operationLimiters.putIfAbsent(
      connectionId,
      () =>
          SshOperationLimiter(maxConcurrentOperations: maxConcurrentOperations),
    );
  }

  String _generateId() {
    return DateTime.now().millisecondsSinceEpoch.toString() +
        Random().nextInt(1000).toString();
  }
}
