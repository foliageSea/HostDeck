import 'dart:async';
import 'package:dartssh2/dartssh2.dart';

import 'ssh_operation_limiter.dart';

class SshSession {
  final String id;
  final String connectionId;
  final SSHClient client;
  final SSHSession? shell;
  final SshOperationLimiter operationLimiter;
  final StreamController<String> _outputController;
  SftpClient? _sftpClient;
  Future<SftpClient>? _sftpInitFuture;
  bool _isClosed = false;

  Stream<String> get output => _outputController.stream;
  StreamController<String> get outputController => _outputController;

  Future<SshOperationPermit> acquireOperation() {
    return operationLimiter.acquire();
  }

  Future<T> runOperation<T>(FutureOr<T> Function() action) {
    return operationLimiter.run(action);
  }

  Future<SftpClient> sftp() async {
    if (_sftpClient != null) return _sftpClient!;

    if (_sftpInitFuture != null) {
      return _sftpInitFuture!;
    }

    _sftpInitFuture = runOperation(client.sftp);
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
    SshOperationLimiter? operationLimiter,
    this.shell,
    StreamController<String>? outputController,
  }) : operationLimiter =
           operationLimiter ?? SshOperationLimiter(maxConcurrentOperations: 4),
       _outputController = outputController ?? StreamController.broadcast();

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
