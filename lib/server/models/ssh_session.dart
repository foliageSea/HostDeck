import 'dart:async';
import 'package:dartssh2/dartssh2.dart';

class SshSession {
  final String id;
  final String connectionId;
  final SSHClient client;
  final SSHSession? shell;
  final StreamController<String> _outputController;
  SftpClient? _sftpClient;
  Future<SftpClient>? _sftpInitFuture;
  bool _isClosed = false;

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
    required this.connectionId,
    required this.client,
    this.shell,
    StreamController<String>? outputController,
  }) : _outputController = outputController ?? StreamController.broadcast();

  Future<void> close() async {
    if (_isClosed) {
      return;
    }

    _isClosed = true;
    _sftpClient?.close();
    shell?.close();
    // Do not close client here, as it may be shared across sessions
    // client.close();
    if (!_outputController.isClosed) {
      await _outputController.close();
    }
  }
}
