import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
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

  /// 没有任何通道租约、且超过该时长没有可见活动时，才回收整条连接。
  ///
  /// 浏览器的 WebSocket 可能"假在线"（TCP 还挂着但收不到数据），所以不能把
  /// 「WS 断开」直接当成「SSH 该断开」，必须留出足够宽限期给客户端重连。
  static const channelIdleGrace = Duration(seconds: 120);

  /// SSH 传输层完全收不到字节超过该时长，判定链路已死。
  static const socketSilenceTimeout = Duration(minutes: 3);

  static const _supervisionInterval = Duration(seconds: 15);
  static const _socketSilenceCheckInterval = Duration(seconds: 30);

  final Map<String, SshSession> _sessions = {};
  final Map<String, Set<SshSessionPurpose>> _sessionPurposes = {};
  final Map<String, SSHClient> _clients = {};
  final Map<String, int?> _connectionServerIds = {};
  final Map<String, SshConnectionMetadata> _connectionMetadata = {};
  final Map<String, SshOperationLimiter> _operationLimiters = {};
  final List<FutureOr<void> Function(String connectionId)>
  _disconnectListeners = [];
  final Map<String, int> _pendingSessionCreations = {};
  final Map<String, Set<String>> _channelLeases = {};
  final Map<String, DateTime> _lastActivityAt = {};
  final Map<String, DateTime> _lastSocketDataAt = {};
  Timer? _idleReaperTimer;
  Timer? _socketSilenceTimer;
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
    String? trackedConnectionId;
    final trackedSocket = _TrackedSshSocket(
      socket,
      onData: () {
        final connectionId = trackedConnectionId;
        if (connectionId != null) {
          _lastSocketDataAt[connectionId] = DateTime.now();
        }
      },
    );
    final client = _clientFactory(
      trackedSocket,
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
    trackedConnectionId = connectionId;
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
    _lastActivityAt[connectionId] = DateTime.now();
    _lastSocketDataAt[connectionId] = DateTime.now();
    _startSupervision();

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

    touch(connectionId);
    _reserveSessionCapacity(connectionId);

    try {
      final shell = await _operationLimiterFor(
        connectionId,
      ).run(() => client.shell(pty: SSHPtyConfig(width: 80, height: 24)));

      final sessionId = _generateId();
      final outputController = StreamController<String>.broadcast();

      // Pipe shell output to controller
      shell.stdout.listen((data) {
        touch(connectionId);
        outputController.add(utf8.decode(data));
      });
      shell.stderr.listen((data) {
        touch(connectionId);
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

    touch(connectionId);
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
    touch(connectionId);
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
            'leaseCount': leaseCount(entry.key),
            'lastActivityAt': _lastActivityAt[entry.key]?.toIso8601String(),
            'lastSocketDataAt': _lastSocketDataAt[entry.key]?.toIso8601String(),
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

  /// 登记一个「还有消费者在用这条连接」的租约。
  ///
  /// 租约只描述「有没有消费者」，不描述「消费者是否还活着」：WebSocket 心跳
  /// 超时后由持有方调用 [detachLease] 释放，真正的 SSH 回收交给
  /// [channelIdleGrace] 的空闲判定，避免一次 WS 抖动把整条连接拆掉。
  void attachLease(String connectionId, String leaseId) {
    if (!_clients.containsKey(connectionId)) {
      return;
    }

    _channelLeases.putIfAbsent(connectionId, () => <String>{}).add(leaseId);
    touch(connectionId);
  }

  void detachLease(String connectionId, String leaseId) {
    final leases = _channelLeases[connectionId];
    if (leases == null) {
      return;
    }

    leases.remove(leaseId);
    if (leases.isEmpty) {
      _channelLeases.remove(connectionId);
    }
  }

  int leaseCount(String connectionId) =>
      _channelLeases[connectionId]?.length ?? 0;

  /// 记录一次「能证明这条连接还在被使用」的可见活动。
  void touch(String connectionId) {
    if (_clients.containsKey(connectionId)) {
      _lastActivityAt[connectionId] = DateTime.now();
    }
  }

  DateTime? lastActivityAt(String connectionId) =>
      _lastActivityAt[connectionId];

  void dispose() {
    _idleReaperTimer?.cancel();
    _idleReaperTimer = null;
    _socketSilenceTimer?.cancel();
    _socketSilenceTimer = null;

    for (final client in _clients.values.toList()) {
      client.close();
    }

    _clients.clear();
    _sessions.clear();
    _sessionPurposes.clear();
    _connectionServerIds.clear();
    _connectionMetadata.clear();
    _operationLimiters.clear();
    _channelLeases.clear();
    _lastActivityAt.clear();
    _lastSocketDataAt.clear();
    _pendingSessionCreations.clear();
  }

  void _startSupervision() {
    _idleReaperTimer ??= Timer.periodic(
      _supervisionInterval,
      (_) => unawaited(_reapIdleConnections()),
    );
    _socketSilenceTimer ??= Timer.periodic(
      _socketSilenceCheckInterval,
      (_) => unawaited(_closeDeadSockets()),
    );
  }

  void _stopSupervisionIfIdle() {
    if (_clients.isNotEmpty) {
      return;
    }

    _idleReaperTimer?.cancel();
    _idleReaperTimer = null;
    _socketSilenceTimer?.cancel();
    _socketSilenceTimer = null;
  }

  Future<void> _reapIdleConnections() async {
    final now = DateTime.now();
    for (final connectionId in _clients.keys.toList()) {
      if (_channelLeases[connectionId]?.isNotEmpty ?? false) {
        continue;
      }

      // 正在执行或排队的 SSH 操作也算「在用」，否则长命令（构建、大文件
      // 传输、docker logs follow）会在无输出期间被误回收。
      final limiter = _operationLimiters[connectionId];
      if (limiter != null &&
          (limiter.runningOperations > 0 || limiter.queuedOperations > 0)) {
        continue;
      }

      final lastActivity = _lastActivityAt[connectionId];
      final idle = lastActivity == null ? null : now.difference(lastActivity);
      if (idle != null && idle < channelIdleGrace) {
        continue;
      }

      logger.warning(
        'Reaping idle SSH connection $connectionId '
        '(no attached channel, idle=${idle?.inSeconds ?? 'unknown'}s)',
      );
      await disconnect(connectionId);
    }
  }

  /// 半开连接检测：对端消失时 TCP 可能长时间保持 ESTABLISHED，
  /// 只有「完全收不到字节」才是可靠信号。dartssh2 每 10 秒发一次
  /// keep-alive 全局请求，正常链路必然有回包，所以沉默超过阈值即可判定已死。
  Future<void> _closeDeadSockets() async {
    final now = DateTime.now();
    for (final connectionId in _clients.keys.toList()) {
      final lastData = _lastSocketDataAt[connectionId];
      if (lastData == null) {
        continue;
      }

      final silence = now.difference(lastData);
      if (silence < socketSilenceTimeout) {
        continue;
      }

      logger.warning(
        'SSH socket silent for ${silence.inSeconds}s on $connectionId; '
        'closing dead connection',
      );
      await disconnect(connectionId);
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
    _channelLeases.remove(connectionId);
    _lastActivityAt.remove(connectionId);
    _lastSocketDataAt.remove(connectionId);
    _stopSupervisionIfIdle();
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

/// 记录 SSH 传输层最后一次收到字节的时间，用于识别半开连接。
class _TrackedSshSocket implements SSHSocket {
  final SSHSocket _inner;
  final void Function() _onData;

  _TrackedSshSocket(this._inner, {required void Function() onData})
    : _onData = onData;

  @override
  Stream<Uint8List> get stream => _inner.stream.map((data) {
    _onData();
    return data;
  });

  @override
  StreamSink<List<int>> get sink => _inner.sink;

  @override
  Future<void> get done => _inner.done;

  @override
  Future<void> close() => _inner.close();

  @override
  void destroy() => _inner.destroy();
}
