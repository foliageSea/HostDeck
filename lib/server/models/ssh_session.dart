import 'dart:async';
import 'package:dartssh2/dartssh2.dart';

class SshSession {
  final String id;
  final SSHClient client;
  final SSHSession shell;
  final StreamController<String> _outputController;
  SftpClient? _sftpClient;
  Future<SftpClient>? _sftpInitFuture;

  Stream<String> get output => _outputController.stream;
  StreamController<String> get outputController => _outputController;

  Future<SftpClient> sftp() async {
    if (_sftpClient != null) return _sftpClient!;

    if (_sftpInitFuture != null) {
      return _sftpInitFuture!;
    }

    _sftpInitFuture = client.sftp();
    try {
      _sftpClient = await _sftpInitFuture;
      return _sftpClient!;
    } catch (e) {
      _sftpInitFuture = null;
      rethrow;
    }
  }

  SshSession({
    required this.id,
    required this.client,
    required this.shell,
    StreamController<String>? outputController,
  }) : _outputController = outputController ?? StreamController.broadcast();

  Future<void> close() async {
    _sftpClient?.close();
    shell.close();
    client.close();
    await _outputController.close();
  }
}
