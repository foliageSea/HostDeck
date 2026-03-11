import 'dart:async';
import 'dart:convert';
import 'package:dartssh2/dartssh2.dart';
import '../models/ssh_session.dart';

class SshService {
  final Map<String, SshSession> _sessions = {};

  Future<SshSession> connect({
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
        ? [
            ...SSHKeyPair.fromPem(privateKey)
          ] 
        : [],
    );

    await client.authenticated;
    
    final shell = await client.shell(
      pty: SSHPtyConfig(
        width: 80,
        height: 24,
      ),
    );

    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final outputController = StreamController<String>.broadcast();
    
    // Pipe shell output to controller
    shell.stdout.listen((data) {
      outputController.add(utf8.decode(data));
    });
    shell.stderr.listen((data) {
      outputController.add(utf8.decode(data));
    });

    final session = SshSession(
      id: id,
      client: client,
      shell: shell,
      outputController: outputController,
    );
    
    _sessions[id] = session;
    
    // Handle session close
    client.done.then((_) {
      closeSession(id);
    });
    
    return session;
  }
  
  SshSession? getSession(String id) => _sessions[id];
  
  Future<void> closeSession(String id) async {
    final session = _sessions[id];
    if (session != null) {
      await session.close();
      _sessions.remove(id);
    }
  }
}
