import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:logging/logging.dart';

import 'package:host_deck/server/core/ssh/ssh_service.dart';
import 'package:host_deck/server/features/code_server/code_server_models.dart';
import 'package:host_deck/server/features/code_server/ide_package_store.dart';
import 'package:host_deck/server/features/code_server/loopback_ssh_bridge.dart';

/// 负责 code-server 会话的安装、启动、健康检查、租约与代理解析。
class CodeServerManager implements CodeServerUpstreamResolver {
  final SshService _sshService;
  final RemoteIdeProvider _provider;
  final IdePackageStore _packages;
  final Logger _log;

  final Map<String, IdeSessionSnapshot> _sessions = {};
  final Map<String, String> _sessionIdToConnection = {};
  final Map<String, LoopbackSshBridge> _bridges = {};
  final Map<String, int> _pids = {};
  final Set<String> _busy = {};
  final Map<String, _CachedPreflight> _preflightCache = {};
  final Random _random = Random.secure();

  CodeServerManager({
    required SshService sshService,
    required RemoteIdeProvider provider,
    required IdePackageStore packages,
    Logger? log,
  }) : _sshService = sshService,
       _provider = provider,
       _packages = packages,
       _log = log ?? Logger('CodeServerManager') {
    _sshService.addDisconnectListener(_handleDisconnect);
  }

  Future<IdePreflight> preflight(
    String connectionId, {
    bool force = false,
  }) async {
    final cached = _preflightCache[connectionId];
    if (!force &&
        cached != null &&
        DateTime.now().difference(cached.at) < const Duration(seconds: 20)) {
      return cached.value;
    }
    final value = await _provider.preflight(connectionId);
    _preflightCache[connectionId] = _CachedPreflight(DateTime.now(), value);
    return value;
  }

  IdeSessionSnapshot? sessionFor(String connectionId) {
    final direct = _sessions[connectionId];
    if (direct != null) return direct;
    final hostKey = hostKeyFor(connectionId);
    if (hostKey == null) return null;
    for (final item in _sessions.values) {
      if (item.hostKey == hostKey && item.state == IdeSessionState.running) {
        return item;
      }
    }
    return null;
  }

  String? hostKeyFor(String connectionId) {
    final targetKey = _sshService.metadataFor(connectionId)?.targetKey;
    if (targetKey == null) return null;
    return sha256.convert(utf8.encode(targetKey)).toString().substring(0, 12);
  }

  Future<IdeSessionSnapshot> install(
    String connectionId, {
    required String packageId,
  }) async {
    final existing = _sessions[connectionId];
    final hostKey = hostKeyFor(connectionId);
    final runningElsewhere = _sessions.values.any(
      (item) =>
          item.state == IdeSessionState.running &&
          item.hostKey.isNotEmpty &&
          item.hostKey == hostKey,
    );
    if ((existing != null && existing.state == IdeSessionState.running) ||
        runningElsewhere) {
      throw StateError('IDE 正在运行，请先停止再安装/升级。');
    }
    _ensureIdle(connectionId);
    _busy.add(connectionId);
    final sessionId = _ensureSession(connectionId).id;
    final operationLease = 'code-server:op:$sessionId';
    _sshService.attachLease(connectionId, operationLease);
    try {
      final preflight = await this.preflight(connectionId, force: true);
      _checkSupported(preflight);

      final package = await _findPackageById(packageId);
      if (package == null) {
        throw StateError('离线包不存在：$packageId');
      }
      if (package.arch != preflight.arch) {
        throw StateError('离线包架构不匹配：目标 ${preflight.arch}，包 ${package.arch}');
      }

      _updateSession(
        connectionId,
        _sessions[connectionId]!.copyWith(
          state: IdeSessionState.installing,
          progress: 0,
          error: null,
        ),
      );
      await _provider.install(
        connectionId,
        package,
        onProgress: (received, total) {
          if (total <= 0) return;
          _updateSession(
            connectionId,
            _sessions[connectionId]!.copyWith(
              progress: (received / total).clamp(0, 1).toDouble(),
            ),
          );
        },
      );
      _preflightCache.remove(connectionId);
      final current = _sessions[connectionId]!;
      _updateSession(
        connectionId,
        current.copyWith(
          state: IdeSessionState.stopped,
          version: package.version,
          progress: null,
        ),
      );
      _log.info('Installed code-server ${package.version} on $connectionId');
      return _sessions[connectionId]!;
    } catch (error, stackTrace) {
      _log.warning(
        'Install code-server failed on $connectionId',
        error,
        stackTrace,
      );
      _updateSession(
        connectionId,
        _sessions[connectionId]!.copyWith(
          state: IdeSessionState.error,
          error: _describe(error),
          progress: null,
        ),
      );
      rethrow;
    } finally {
      _sshService.detachLease(connectionId, operationLease);
      _busy.remove(connectionId);
      _sessionIdToConnection[sessionId] = connectionId;
    }
  }

  Future<IdeSessionSnapshot> start(
    String connectionId, {
    String? folder,
  }) async {
    final existing = _sessions[connectionId];
    if (existing != null && existing.state == IdeSessionState.running) {
      return existing;
    }
    final hostKey = hostKeyFor(connectionId);
    if (hostKey == null) {
      throw StateError('SSH 连接元数据缺失，无法确定远端数据目录。');
    }
    for (final item in _sessions.values) {
      if (item.hostKey == hostKey && item.state == IdeSessionState.running) {
        return item;
      }
    }

    _ensureIdle(connectionId);
    _busy.add(connectionId);

    final sessionId = _ensureSession(connectionId).id;
    _sessionIdToConnection[sessionId] = connectionId;
    final operationLease = 'code-server:op:$sessionId';
    _sshService.attachLease(connectionId, operationLease);
    try {
      final preflight = await this.preflight(connectionId, force: true);
      _checkSupported(preflight);

      var version = preflight.installedVersion;
      if (version == null) {
        final package = await _pickPackage(preflight.arch);
        if (package == null) {
          throw StateError(
            '目标机未安装 code-server，且没有 ${preflight.arch} 架构的离线包；请先在设置中上传离线包。',
          );
        }
        _updateSession(
          connectionId,
          _sessions[connectionId]!.copyWith(
            state: IdeSessionState.installing,
            progress: 0,
            error: null,
            folder: folder,
          ),
        );
        await _provider.install(
          connectionId,
          package,
          onProgress: (received, total) {
            if (total <= 0) return;
            _updateSession(
              connectionId,
              _sessions[connectionId]!.copyWith(
                progress: (received / total).clamp(0, 1).toDouble(),
              ),
            );
          },
        );
        version = package.version;
      }

      _updateSession(
        connectionId,
        _sessions[connectionId]!.copyWith(
          state: IdeSessionState.starting,
          version: version,
          error: null,
          folder: folder,
        ),
      );

      final launch = await _provider.start(
        connectionId,
        sessionId: sessionId,
        hostKey: hostKey,
        version: version,
      );
      _pids[connectionId] = launch.pid;

      final bridge = await LoopbackSshBridge.start(
        sshService: _sshService,
        connectionId: connectionId,
        remotePort: launch.port,
      );
      _bridges[connectionId] = bridge;

      await _waitForHealth(bridge.localPort);
      _sshService.attachLease(connectionId, 'code-server:$sessionId');

      final snapshot = _sessions[connectionId]!.copyWith(
        state: IdeSessionState.running,
        version: launch.version,
        progress: null,
        startedAt: DateTime.now(),
      );
      _updateSession(connectionId, snapshot);
      _log.info(
        'IDE session $sessionId running on $connectionId (port ${launch.port})',
      );
      return snapshot;
    } catch (error, stackTrace) {
      _log.warning(
        'Start code-server failed on $connectionId',
        error,
        stackTrace,
      );
      await _cleanupConnection(connectionId, killRemote: true);
      _updateSession(
        connectionId,
        _sessions[connectionId]!.copyWith(
          state: IdeSessionState.error,
          error: _describe(error),
          progress: null,
        ),
      );
      rethrow;
    } finally {
      _sshService.detachLease(connectionId, operationLease);
      _busy.remove(connectionId);
    }
  }

  Future<IdeSessionSnapshot> stop(String connectionId) async {
    final snapshot = _sessions[connectionId];
    if (snapshot == null) {
      throw StateError('IDE 会话不存在。');
    }
    _updateSession(
      connectionId,
      snapshot.copyWith(state: IdeSessionState.stopping, error: null),
    );
    await _cleanupConnection(connectionId, killRemote: true);
    final stopped = _sessions[connectionId]!.copyWith(
      state: IdeSessionState.stopped,
      progress: null,
      error: null,
    );
    _updateSession(connectionId, stopped);
    return stopped;
  }

  Future<void> _cleanupConnection(
    String connectionId, {
    required bool killRemote,
  }) async {
    final bridge = _bridges.remove(connectionId);
    await bridge?.close();

    final pid = _pids.remove(connectionId);
    final snapshot = _sessions[connectionId];
    if (killRemote && pid != null && snapshot != null) {
      try {
        await _provider.stop(connectionId, sessionId: snapshot.id, pid: pid);
      } catch (error) {
        _log.fine('Stop remote code-server failed: $error');
      }
    }

    if (snapshot != null) {
      try {
        _sshService.detachLease(connectionId, 'code-server:${snapshot.id}');
      } catch (_) {
        // 连接已断开时忽略。
      }
    }
  }

  Future<void> _waitForHealth(int port) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    try {
      final deadline = DateTime.now().add(const Duration(seconds: 40));
      Object? lastError;
      while (DateTime.now().isBefore(deadline)) {
        try {
          final request = await client.getUrl(
            Uri.parse('http://127.0.0.1:$port/healthz'),
          );
          final response = await request.close().timeout(
            const Duration(seconds: 3),
          );
          await response.drain<void>();
          if (response.statusCode == 200) return;
          lastError = StateError('healthz ${response.statusCode}');
        } catch (error) {
          lastError = error;
        }
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      throw StateError('code-server 健康检查失败：${lastError ?? 'timeout'}');
    } finally {
      client.close(force: true);
    }
  }

  Future<IdePackage?> _pickPackage(String arch) async {
    final packages = await _packages.list();
    final candidates = packages.where((item) => item.arch == arch).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return candidates.isEmpty ? null : candidates.first;
  }

  Future<IdePackage?> _findPackageById(String id) async {
    final packages = await _packages.list();
    for (final item in packages) {
      if (item.id == id) return item;
    }
    return null;
  }

  void _checkSupported(IdePreflight preflight) {
    if (!preflight.supported) {
      throw StateError(preflight.issues.join('；'));
    }
  }

  void _ensureIdle(String connectionId) {
    if (_busy.contains(connectionId)) {
      throw StateError('该连接已有 IDE 操作正在进行。');
    }
  }

  IdeSessionSnapshot _ensureSession(String connectionId) {
    final existing = _sessions[connectionId];
    if (existing != null) return existing;
    final snapshot = IdeSessionSnapshot(
      id: _newSessionId(),
      connectionId: connectionId,
      hostKey: hostKeyFor(connectionId) ?? '',
      folder: null,
      state: IdeSessionState.stopped,
      error: null,
      version: null,
      progress: null,
      startedAt: null,
    );
    _sessions[connectionId] = snapshot;
    _sessionIdToConnection[snapshot.id] = connectionId;
    return snapshot;
  }

  void _updateSession(String connectionId, IdeSessionSnapshot snapshot) {
    _sessions[connectionId] = snapshot;
    _sessionIdToConnection[snapshot.id] = connectionId;
  }

  String _newSessionId() {
    final values = List<int>.generate(6, (_) => _random.nextInt(256));
    return values
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  Future<void> _handleDisconnect(String connectionId) async {
    if (!_sessions.containsKey(connectionId)) return;
    await _cleanupConnection(connectionId, killRemote: false);
    final snapshot = _sessions[connectionId];
    if (snapshot != null) {
      _updateSession(
        connectionId,
        snapshot.copyWith(
          state: IdeSessionState.stopped,
          error: 'SSH 连接已断开',
          progress: null,
        ),
      );
    }
  }

  @override
  Future<CodeServerUpstream?> resolve(String sessionId) async {
    final connectionId = _sessionIdToConnection[sessionId];
    if (connectionId == null) return null;
    final snapshot = _sessions[connectionId];
    if (snapshot == null ||
        snapshot.state != IdeSessionState.running ||
        snapshot.id != sessionId) {
      return null;
    }
    final bridge = _bridges[connectionId];
    if (bridge == null) return null;
    return CodeServerUpstream('127.0.0.1', bridge.localPort);
  }

  void touch(String sessionId) {
    final connectionId = _sessionIdToConnection[sessionId];
    if (connectionId != null) _sshService.touch(connectionId);
  }

  Future<void> dispose() async {
    for (final connectionId in _sessions.keys.toList()) {
      await _cleanupConnection(connectionId, killRemote: true);
    }
    _sessions.clear();
    _sessionIdToConnection.clear();
    _pids.clear();
    _bridges.clear();
  }

  String _describe(Object error) =>
      error is StateError ? error.message : error.toString();
}

class _CachedPreflight {
  final DateTime at;
  final IdePreflight value;

  const _CachedPreflight(this.at, this.value);
}
