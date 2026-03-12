import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssh_tool/server/services/monitor_service.dart';
import 'package:ssh_tool/server/repositories/ssh_repository.dart';
import 'package:ssh_tool/server/models/ssh_session.dart';
import 'package:ssh_tool/server/models/file_item.dart';
import 'package:dartssh2/dartssh2.dart';

// Manual Mock
class MockSshRepository implements SshRepository {
  @override
  Future<String> exec(SshSession session, String command) async {
    if (command.contains('grep Mem')) {
      return "Mem:           8000        4000         480          18        3627        3829";
    }
    if (command.contains('df -h')) {
      return "45%";
    }
    if (command.contains('uptime')) {
      return " 13:22:01 up 1 day,  3:10,  1 user,  load average: 0.50, 0.05, 0.01";
    }
    return "";
  }

  @override
  Future<List<FileItem>> listFiles(SshSession session, String path) =>
      throw UnimplementedError();
  @override
  Future<Stream<Uint8List>> readFileStream(SshSession session, String path) =>
      throw UnimplementedError();
  @override
  Future<void> writeFileStream(
    SshSession session,
    String path,
    Stream<List<int>> content,
  ) => throw UnimplementedError();
  @override
  Future<void> rename(SshSession session, String oldPath, String newPath) =>
      throw UnimplementedError();
  @override
  Future<void> mkdir(SshSession session, String path) =>
      throw UnimplementedError();
  @override
  Future<void> copy(SshSession session, String source, String target) =>
      throw UnimplementedError();
  @override
  Future<Stream<Uint8List>> downloadBatch(
    SshSession session,
    List<String> paths,
  ) => throw UnimplementedError();
  @override
  Future<void> delete(SshSession session, String path) =>
      throw UnimplementedError();
  @override
  void resize(SshSession session, int width, int height) {}
  @override
  void writeToShell(SshSession session, String data) {}
}

class MockSshSession implements SshSession {
  @override
  String get id => 'test_id';
  @override
  String get connectionId => 'test_connection_id';
  @override
  SSHClient get client => throw UnimplementedError();
  @override
  SSHSession get shell => throw UnimplementedError();
  @override
  Stream<String> get output => Stream.empty();
  @override
  StreamController<String> get outputController => StreamController();
  @override
  Future<SftpClient> sftp() => throw UnimplementedError();
  @override
  Future<void> close() async {}
}

void main() {
  test('MonitorService parses system status correctly', () async {
    final repo = MockSshRepository();
    final service = MonitorService(repo);
    final session = MockSshSession();

    final status = await service.getSystemStatus(session);

    expect(status.cpu, equals('0.50'));
    expect(status.ram.total, equals(8000));
    expect(status.ram.used, equals(4000));
    expect(status.disk, equals('45%'));
  });
}
