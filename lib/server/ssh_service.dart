import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

class SshSession {
  final String id;
  final SSHClient client;
  final SSHSession shell;
  final StreamController<String> _outputController = StreamController.broadcast();
  
  Stream<String> get output => _outputController.stream;

  SshSession(this.id, this.client, this.shell) {
    shell.stdout.listen((data) {
      _outputController.add(utf8.decode(data));
    });
    shell.stderr.listen((data) {
      _outputController.add(utf8.decode(data));
    });
  }

  void write(String data) {
    shell.write(Uint8List.fromList(utf8.encode(data)));
  }
  
  void resize(int width, int height) {
    shell.resizeTerminal(width, height);
  }

  Future<void> close() async {
    shell.close();
    client.close();
    await _outputController.close();
  }

  Future<String> exec(String command) async {
    final result = await client.run(command);
    return utf8.decode(result);
  }

  Future<List<Map<String, dynamic>>> listFiles(String path) async {
    final sftp = await client.sftp();
    try {
      final items = await sftp.listdir(path);
      return items.map((item) => {
        'filename': item.filename,
        'longname': item.longname,
        'isDirectory': item.attr.isDirectory,
        'size': item.attr.size,
        'mtime': item.attr.modifyTime,
      }).toList();
    } finally {
      sftp.close();
    }
  }

  Future<Uint8List> readFile(String path) async {
    final sftp = await client.sftp();
    try {
      final file = await sftp.open(path);
      // readBytes reads up to length. If we want all, we might need loop or get size first.
      // But file.readBytes() in dartssh2 might handle it?
      // Actually SftpFile.readBytes defaults to reading a chunk.
      // Better to use read(length).
      final stat = await file.stat();
      final size = stat.size ?? 0;
      if (size == 0) return Uint8List(0);
      // Caution: large files might crash memory. For now limit to small files (editor).
      return await file.readBytes(length: size); 
    } finally {
      sftp.close();
    }
  }
  
  Future<void> writeFile(String path, Uint8List content) async {
    final sftp = await client.sftp();
    try {
      final file = await sftp.open(path, mode: SftpFileOpenMode.write | SftpFileOpenMode.create | SftpFileOpenMode.truncate);
      await file.writeBytes(content);
    } finally {
      sftp.close();
    }
  }

  Future<void> delete(String path) async {
    final sftp = await client.sftp();
    try {
      final stat = await sftp.stat(path);
      if (stat.isDirectory) {
        await sftp.rmdir(path);
      } else {
        await sftp.remove(path);
      }
    } finally {
      sftp.close();
    }
  }
}

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
            // Basic identity parsing - might need more robust handling
            ...SSHKeyPair.fromPem(privateKey)
          ] 
        : [],
    );

    // Wait for authentication
    await client.authenticated;
    
    final shell = await client.shell(
      pty: SSHPtyConfig(
        width: 80,
        height: 24,
      ),
    );

    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final session = SshSession(id, client, shell);
    _sessions[id] = session;
    
    return session;
  }
  
  SshSession? getSession(String id) => _sessions[id];
  
  Future<void> closeSession(String id) async {
    await _sessions[id]?.close();
    _sessions.remove(id);
  }
}
