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
  int _callCount = 0;

  @override
  Future<Uint8List> execBytes(SshSession session, String command) async {
    return Uint8List.fromList((await exec(session, command)).codeUnits);
  }

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
    if (command.contains('top')) {
      return "%Cpu(s):  0.3 us,  0.3 sy,  0.0 ni, 99.3 id,  0.0 wa,  0.0 hi,  0.0 si,  0.0 st";
    }
    if (command.contains('/proc/net/dev')) {
      _callCount++;
      // Simulate increasing traffic
      // 1st call: rx=1000, tx=1000
      // 2nd call: rx=2000, tx=3000
      final rx = 1000 * _callCount;
      final tx = 1000 + (2000 * (_callCount - 1)); // 1000, 3000, ...
      return """
Inter-|   Receive                                                |  Transmit
 face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed
    lo: 6445690   76906    0    0    0     0          0         0  6445690   76906    0    0    0     0       0          0
  eth0: $rx 1446736    0    0    0     0          0         0 $tx 1034567    0    0    0     0       0          0
""";
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
  Future<void> extract(
    SshSession session,
    String archivePath,
    String targetPath,
  ) => throw UnimplementedError();
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

  test('MonitorService calculates network speed', () async {
    final repo = MockSshRepository();
    final service = MonitorService(repo);
    final session = MockSshSession();

    // First call: initial snapshot
    var status = await service.getSystemStatus(session);
    expect(status.network, isNotNull);
    expect(status.network!.downloadSpeed, equals(0.0));
    expect(status.network!.uploadSpeed, equals(0.0));

    // Wait a bit to ensure non-zero duration
    await Future.delayed(const Duration(milliseconds: 100));

    // Second call
    // MockSshRepository increments rx by 1000, tx by 2000 per call
    status = await service.getSystemStatus(session);
    expect(status.network!.downloadSpeed, greaterThan(0));
    expect(status.network!.uploadSpeed, greaterThan(0));
  });
}
