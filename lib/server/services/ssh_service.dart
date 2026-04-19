import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:dartssh2/dartssh2.dart';
import '../models/ssh_session.dart';

class SshService {
  final Map<String, SshSession> _sessions = {};
  final Map<String, SSHClient> _clients = {};

  Future<String> connect({
    required String host,
    required int port,
    required String username,
    String? password,
    String? privateKey,
  }) async {
    final socket = await SSHSocket.connect(host, port);

    final client = SSHClient(
      socket,
      username: username,
      onPasswordRequest: password != null ? () => password : null,
      identities: privateKey != null && privateKey.trim().isNotEmpty
          ? [...SSHKeyPair.fromPem(privateKey)]
          : [],
    );

    await client.authenticated;

    final connectionId = _generateId();
    _clients[connectionId] = client;

    // Handle unexpected disconnection
    client.done.then((_) {
      _disconnectInternal(connectionId);
    });

    return connectionId;
  }

  Future<SshSession> createShell(String connectionId) async {
    final client = _clients[connectionId];
    if (client == null) {
      throw Exception('Connection not found: $connectionId');
    }

    if (client.isClosed) {
      _disconnectInternal(connectionId);
      throw Exception('Connection is closed');
    }

    final shell = await client.shell(pty: SSHPtyConfig(width: 80, height: 24));

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
      shell: shell,
      outputController: outputController,
    );

    _sessions[sessionId] = session;

    // Handle client disconnection (only once per client usually, but safe to add listener?)
    // Actually client.done is a future. We should set it up when client is created.
    // But we didn't do it in connect() fully.
    // Let's do it here? No, better in connect.
    // However, if we do it in connect, we need to know how to clean up.

    return session;
  }

  Future<SshSession> createSftpSession(String connectionId) async {
    final client = _clients[connectionId];
    if (client == null) {
      throw Exception('Connection not found: $connectionId');
    }

    if (client.isClosed) {
      _disconnectInternal(connectionId);
      throw Exception('Connection is closed');
    }

    final sessionId = _generateId();
    // Create session without shell
    final session = SshSession(
      id: sessionId,
      connectionId: connectionId,
      client: client,
      shell: null,
    );

    _sessions[sessionId] = session;
    return session;
  }

  // Helper to setup client cleanup.
  // Since we modified connect to return SshSession via createShell,
  // we need to attach the listener in connect or right after client creation.
  // But wait, connect calls createShell.

  // Let's fix connect() to attach listener.

  SshSession? getSession(String id) => _sessions[id];

  SSHClient? getClient(String connectionId) => _clients[connectionId];

  Map<String, dynamic> getRuntimeSnapshot() {
    final sessionCounts = <String, int>{};
    for (final session in _sessions.values) {
      sessionCounts.update(
        session.connectionId,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }

    final clients = _clients.entries
        .map(
          (entry) => {
            'connectionId': entry.key,
            'isClosed': entry.value.isClosed,
            'sessionCount': sessionCounts[entry.key] ?? 0,
          },
        )
        .toList()
      ..sort(
        (left, right) => (left['connectionId'] as String).compareTo(
          right['connectionId'] as String,
        ),
      );

    final sessions = _sessions.values
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
    final client = _clients[connectionId];
    if (client != null) {
      client.close();
      _disconnectInternal(connectionId);
    }
  }

  void _disconnectInternal(String connectionId) {
    final sessionsToRemove = _sessions.values
        .where((s) => s.connectionId == connectionId)
        .toList();
    for (final session in sessionsToRemove) {
      // We don't await here because this might be called from sync context or fire-and-forget
      session.close();
      _sessions.remove(session.id);
    }
    _clients.remove(connectionId);
  }

  String _generateId() {
    return DateTime.now().millisecondsSinceEpoch.toString() +
        Random().nextInt(1000).toString();
  }
}
