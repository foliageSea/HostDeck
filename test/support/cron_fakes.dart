import 'dart:async';

import 'package:dartssh2/dartssh2.dart';

import 'package:host_deck/server/core/ssh/ssh_connection_handle.dart';
import 'package:host_deck/server/core/ssh/ssh_operation_limiter.dart';
import 'package:host_deck/server/core/ssh/ssh_repository.dart';
import 'package:host_deck/server/core/ssh/ssh_session.dart';

/// In-memory crontab with artificial latency so unserialized callers interleave.
class FakeCrontabRepository extends SshRepository {
  String crontab = '';
  String? readError;
  bool writeFails = false;
  String writeError = 'bad crontab';
  bool failNextWrite = false;
  int writes = 0;

  /// The `login` flag of every command run, in order.
  final List<bool> loginFlags = [];

  /// Contents written by `cat > <path>`, keyed by path.
  final Map<String, String> files = {};

  @override
  Future<SshExecResult> execWithResult(
    SshOperationContext session,
    String command, {
    String? cwd,
    Duration? timeout,
    String? stdin,
    int? maxOutputBytes,
    bool login = true,
  }) async {
    loginFlags.add(login);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    if (command.startsWith('cat > ')) {
      files[command.substring('cat > '.length)] = stdin ?? '';
      return _result(0);
    }
    if (command == 'crontab -l') {
      if (readError != null) return _result(1, stderr: readError!);
      if (crontab.isEmpty) return _result(1, stderr: 'no crontab for user');
      return _result(0, stdout: crontab);
    }
    if (command == 'crontab -') {
      if (writeFails || failNextWrite) {
        failNextWrite = false;
        return _result(1, stderr: writeError);
      }
      writes++;
      crontab = stdin ?? '';
      return _result(0);
    }
    return _result(0);
  }

  SshExecResult _result(int code, {String stdout = '', String stderr = ''}) =>
      SshExecResult(
        exitCode: code,
        stdout: stdout,
        stderr: stderr,
        durationMs: 0,
      );
}

class FakeSshSession implements SshSession {
  FakeSshSession({this.connectionId = 'connection-1'});

  @override
  final String connectionId;

  @override
  SSHClient get client => throw UnimplementedError();

  @override
  String get id => 'session-1';

  @override
  final SshOperationLimiter operationLimiter = SshOperationLimiter(
    maxConcurrentOperations: 4,
  );

  @override
  Stream<String> get output => const Stream.empty();

  @override
  StreamController<String> get outputController => StreamController.broadcast();

  @override
  SSHSession? get shell => null;

  @override
  Future<SftpClient> sftp() => throw UnimplementedError();

  @override
  Future<SshOperationPermit> acquireOperation() => operationLimiter.acquire();

  @override
  Future<T> runOperation<T>(FutureOr<T> Function() action) =>
      operationLimiter.run(action);

  @override
  Future<void> close() async {}
}
