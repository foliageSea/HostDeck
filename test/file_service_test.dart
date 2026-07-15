import 'dart:async';
import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:host_deck/server/core/ssh/ssh_operation_limiter.dart';
import 'package:host_deck/server/core/ssh/ssh_repository.dart';
import 'package:host_deck/server/core/ssh/ssh_session.dart';
import 'package:host_deck/server/features/files/file_service.dart';

class _RecordingSshRepository extends SshRepository {
  String? path;
  List<int>? writtenBytes;

  @override
  Future<void> writeFileStream(
    SshSession session,
    String path,
    Stream<List<int>> content,
  ) async {
    this.path = path;
    writtenBytes = await content.expand((chunk) => chunk).toList();
  }
}

class _FakeSshSession implements SshSession {
  @override
  SSHClient get client => throw UnimplementedError();

  @override
  String get connectionId => 'connection-1';

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
  Future<T> runOperation<T>(FutureOr<T> Function() action) {
    return operationLimiter.run(action);
  }

  @override
  Future<void> close() async {}
}

void main() {
  test(
    'FileService forwards complete write content to the SSH repository',
    () async {
      final repository = _RecordingSshRepository();
      final service = FileService(repository);

      await service.writeFileStream(
        _FakeSshSession(),
        '/etc/hostdeck.conf',
        Stream.fromIterable([utf8.encode('enabled='), utf8.encode('true\n')]),
      );

      expect(repository.path, '/etc/hostdeck.conf');
      expect(utf8.decode(repository.writtenBytes!), 'enabled=true\n');
    },
  );
}
