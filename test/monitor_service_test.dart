import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:host_deck/server/core/ssh/ssh_operation_limiter.dart';
import 'package:host_deck/server/core/ssh/ssh_repository.dart';
import 'package:host_deck/server/core/ssh/ssh_session.dart';
import 'package:host_deck/server/features/files/file_item.dart';
import 'package:host_deck/server/features/system/monitor_service.dart';
import 'package:dartssh2/dartssh2.dart';

// Manual Mock
class MockSshRepository implements SshRepository {
  int _callCount = 0;

  @override
  Future<Uint8List> execBytes(SshSession session, String command) async {
    return Uint8List.fromList((await exec(session, command)).codeUnits);
  }

  @override
  Future<int> getDirectorySize(SshSession session, String path) =>
      throw UnimplementedError();

  @override
  Future<String> exec(SshSession session, String command) async {
    if (command.contains('grep Mem')) {
      return "Mem:           8000        4000         480          18        3627        3829";
    }
    if (command.contains('df -h')) {
      return "45%";
    }
    if (command.trim() == 'uptime') {
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
    if (command.contains("printf 'hostname=%s")) {
      return """
hostname=software-order-1
distribution=Ubuntu 22.04.3 LTS
kernel=5.15.0-179-generic
architecture=x86_64
hostAddress=192.168.0.221
bootTime=2026-05-26 16:26:13
uptime=2 weeks, 1 day, 3 hours, 12 minutes
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
  Future<void> chmod(
    SshSession session,
    String path,
    String mode, {
    bool recursive = false,
  }) => throw UnimplementedError();
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

  @override
  Future<SshExecResult> execWithResult(
    SshSession _,
    String command, {
    String? cwd,
    Duration? timeout,
    String? stdin,
  }) {
    // TODO: implement execWithResult
    throw UnimplementedError();
  }
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
  final SshOperationLimiter operationLimiter = SshOperationLimiter(
    maxConcurrentOperations: 4,
  );
  @override
  Stream<String> get output => Stream.empty();
  @override
  StreamController<String> get outputController => StreamController();
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
  test('MonitorService parses system status correctly', () async {
    final repo = MockSshRepository();
    final service = MonitorService(repo);
    final session = MockSshSession();

    final status = await service.getSystemStatus(session);

    expect(status.cpu, equals('0.50'));
    expect(status.ram.total, equals(8000));
    expect(status.ram.used, equals(4000));
    expect(status.disk, equals('45%'));
    expect(status.systemInfo?.hostname, equals('software-order-1'));
    expect(status.systemInfo?.distribution, equals('Ubuntu 22.04.3 LTS'));
    expect(status.systemInfo?.kernel, equals('5.15.0-179-generic'));
    expect(status.systemInfo?.architecture, equals('x86_64'));
    expect(status.systemInfo?.hostAddress, equals('192.168.0.221'));
    expect(status.systemInfo?.bootTime, equals('2026-05-26 16:26:13'));
    expect(
      status.systemInfo?.uptime,
      equals('2 weeks, 1 day, 3 hours, 12 minutes'),
    );
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
