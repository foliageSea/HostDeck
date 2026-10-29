import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:host_deck/server/core/ssh/ssh_connection_handle.dart';
import 'package:host_deck/server/core/ssh/ssh_operation_limiter.dart';
import 'package:host_deck/server/core/ssh/ssh_repository.dart';
import 'package:host_deck/server/core/ssh/ssh_service.dart';
import 'package:host_deck/server/core/ssh/ssh_session.dart';
import 'package:host_deck/server/features/code_server/code_server_models.dart';
import 'package:host_deck/server/features/code_server/loopback_ssh_bridge.dart';
import 'package:host_deck/server/features/code_server/remote_ide_provider.dart';

typedef _ExecHandler = SshExecResult Function(String command);

void main() {
  group('SshRemoteIdeProvider preflight', () {
    late Directory tempDir;
    late _FakeSshService sshService;
    late _FakeSshRepository repository;
    late SshRemoteIdeProvider provider;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('hostdeck_ide_probe_');
      sshService = _FakeSshService();
      repository = _FakeSshRepository((command) => _ok());
      provider = SshRemoteIdeProvider(sshService, repository);
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('detects a supported x86_64 target', () async {
      repository.handler = _preflightHandler();

      final preflight = await provider.preflight('connection-1');

      expect(preflight.arch, 'amd64');
      expect(preflight.libc, 'glibc 2.31');
      expect(preflight.diskFreeBytes, 5000000 * 1024);
      expect(preflight.installedVersion, isNull);
      expect(preflight.issues, isEmpty);
      expect(preflight.supported, isTrue);
      expect(preflight.hasDiskSpace, isTrue);
      expect(sshService.purposes, [SshSessionPurpose.codeServer]);
      expect(repository.calls, isNotEmpty);
      for (final call in repository.calls) {
        expect(call.timeout, isNotNull, reason: call.command);
        expect(call.login, isFalse, reason: call.command);
      }
    });

    test(
      'reports unsupported arch, musl, low disk and missing tools',
      () async {
        repository.handler = _preflightHandler(
          arch: 'armv7l',
          libc: 'musl libc (armv7l)',
          availableKb: '1000',
          tools: const {'sha256sum'},
        );

        final preflight = await provider.preflight('connection-1');

        expect(preflight.arch, 'armv7l');
        expect(preflight.supported, isFalse);
        expect(preflight.hasDiskSpace, isFalse);
        expect(preflight.issues.join('；'), contains('不支持的远端架构'));
        expect(preflight.issues.join('；'), contains('musl libc'));
        expect(preflight.issues.join('；'), contains('磁盘可用空间不足'));
        expect(preflight.issues.join('；'), contains('缺少 tar'));
        expect(preflight.issues.join('；'), contains('缺少 setsid/nohup'));
      },
    );

    test('reports glibc versions below 2.28', () async {
      repository.handler = _preflightHandler(libc: 'ldd (GNU libc) 2.17');

      final preflight = await provider.preflight('connection-1');

      expect(preflight.libc, 'ldd (GNU libc) 2.17');
      expect(preflight.issues.join('；'), contains('glibc 版本过低'));
    });

    test('reads the expected installed version', () async {
      repository.handler = _preflightHandler(installedVersion: '4.143.1');

      final preflight = await provider.preflight(
        'connection-1',
        expectedVersion: '4.143.1',
      );

      expect(preflight.installedVersion, '4.143.1');
      expect(
        repository.calls.any(
          (call) => call.command.contains(
            '/.local/lib/hostdeck/code-server/4.143.1/bin/code-server',
          ),
        ),
        isTrue,
      );
    });
  });

  group('SshRemoteIdeProvider install', () {
    late Directory tempDir;
    late _FakeSshService sshService;
    late _FakeSshRepository repository;
    late SshRemoteIdeProvider provider;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('hostdeck_ide_install_');
      sshService = _FakeSshService();
      repository = _FakeSshRepository((command) => _ok());
      provider = SshRemoteIdeProvider(sshService, repository);
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('streams the archive, verifies sha256 and installs it', () async {
      final package = await _createPackage(tempDir);
      repository.handler = _installHandler(package);

      final progress = <List<int>>[];
      await provider.install(
        'connection-1',
        package,
        onProgress: (received, total) => progress.add([received, total]),
      );

      expect(
        repository.uploadedPath,
        '/home/tester/.local/share/hostdeck/code-server/tmp/'
        '${package.id}.tar.gz',
      );
      expect(repository.uploadedBytes, _archiveBytes());
      expect(progress.last, [package.size, package.size]);
      expect(repository.uploadChunks, greaterThan(0));
      expect(
        sshService.purposes.every(
          (purpose) => purpose == SshSessionPurpose.codeServer,
        ),
        isTrue,
      );

      final extractIndex = repository.calls.indexWhere(
        (call) => call.command.contains('tar -xzf'),
      );
      final versionIndex = repository.calls.indexWhere(
        (call) => call.command.contains('--version'),
      );
      expect(extractIndex, greaterThanOrEqualTo(0));
      expect(versionIndex, greaterThan(extractIndex));
      expect(
        repository.calls.any(
          (call) =>
              call.command.startsWith('rm -rf') &&
              call.command.contains(package.id),
        ),
        isTrue,
      );
    });

    test(
      'retries the version probe before reporting an unknown version',
      () async {
        final package = await _createPackage(tempDir);
        final base = _installHandler(package);
        var probes = 0;
        repository.handler = (command) {
          if (command.contains('--version')) {
            probes++;
            return probes == 1
                ? _ok('')
                : _ok('4.143.1${String.fromCharCode(10)}');
          }
          return base(command);
        };

        await provider.install('connection-1', package);

        expect(probes, greaterThanOrEqualTo(2));
      },
    );

    test('fails and cleans up when the remote sha256 differs', () async {
      final package = await _createPackage(tempDir);
      repository.handler = _installHandler(package, remoteSha256: 'deadbeef');

      await expectLater(
        provider.install('connection-1', package),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('sha256 校验失败'),
          ),
        ),
      );

      expect(
        repository.calls.any(
          (call) =>
              call.command.startsWith('rm -rf') &&
              call.command.contains(package.id),
        ),
        isTrue,
      );
      expect(
        repository.calls.any((call) => call.command.contains('tar -xzf')),
        isFalse,
      );
    });

    test(
      'fails and uninstalls when the installed version mismatches',
      () async {
        final package = await _createPackage(tempDir);
        repository.handler = _installHandler(package, remoteVersion: '4.0.0');

        await expectLater(
          provider.install('connection-1', package),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              contains('装载校验失败'),
            ),
          ),
        );

        expect(
          repository.calls.any(
            (call) =>
                call.command.startsWith('rm -rf') &&
                call.command.contains(
                  '/.local/lib/hostdeck/code-server/4.143.1',
                ),
          ),
          isTrue,
        );
      },
    );

    test('stops before uploading when cancelled', () async {
      final package = await _createPackage(tempDir);

      await expectLater(
        provider.install('connection-1', package, isCancelled: () => true),
        throwsA(isA<IdeInstallCancelledException>()),
      );

      expect(repository.uploadedBytes, isNull);
      expect(repository.calls, isEmpty);
    });

    test('rejects packages outside amd64/arm64', () async {
      final package = await _createPackage(tempDir, arch: 'armv7l');

      await expectLater(
        provider.install('connection-1', package),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('SshRemoteIdeProvider start/stop', () {
    late _FakeSshService sshService;
    late _FakeSshRepository repository;
    late SshRemoteIdeProvider provider;

    const sessionId = 'abc123def456';
    const hostKey = 'deadbeef1234';
    const version = '4.143.1';

    setUp(() {
      sshService = _FakeSshService();
      repository = _FakeSshRepository((command) => _ok());
      provider = SshRemoteIdeProvider(sshService, repository);
    });

    test(
      'uninstall removes only managed installation and preserves data and projects',
      () async {
        final home = await Directory.systemTemp.createTemp(
          "hostdeck uninstall ' ",
        );
        addTearDown(() => home.delete(recursive: true));
        final install = Directory(
          '${home.path}/.local/lib/hostdeck/code-server',
        );
        await install.create(recursive: true);
        await File('${install.path}/binary').writeAsString('managed');
        final data = File(
          '${home.path}/.local/share/hostdeck/code-server/key/extensions/keep',
        );
        await data.parent.create(recursive: true);
        await data.writeAsString('extension');
        final project = File('${home.path}/project.txt');
        await project.writeAsString('project');
        repository.handler = (command) {
          if (command.startsWith("printf '%s")) return _ok('${home.path}\n');
          final result = Process.runSync('sh', ['-c', command]);
          return SshExecResult(
            exitCode: result.exitCode,
            stdout: result.stdout as String,
            stderr: result.stderr as String,
            durationMs: 0,
          );
        };
        await provider.uninstall('connection-1');
        expect(install.existsSync(), isFalse);
        expect(await data.readAsString(), 'extension');
        expect(await project.readAsString(), 'project');
        await provider.uninstall('connection-1');
        expect(repository.calls.last.timeout, isNotNull);
      },
    );

    test('uninstall rejects symlinked installation ancestors', () async {
      final home = await Directory.systemTemp.createTemp(
        'hostdeck_uninstall_link_',
      );
      addTearDown(() => home.delete(recursive: true));
      final outside = Directory('${home.path}/outside');
      await outside.create();
      final keep = File('${outside.path}/keep');
      await keep.writeAsString('safe');
      await Link('${home.path}/.local').create(outside.path);
      repository.handler = (command) {
        if (command.startsWith("printf '%s")) return _ok('${home.path}\n');
        final result = Process.runSync('sh', ['-c', command]);
        return SshExecResult(
          exitCode: result.exitCode,
          stdout: result.stdout as String,
          stderr: result.stderr as String,
          durationMs: 0,
        );
      };
      await expectLater(provider.uninstall('connection-1'), throwsStateError);
      expect(await keep.readAsString(), 'safe');
    });

    test(
      'uninstall and stop reject unsuccessful or unknown exit status',
      () async {
        for (final exitCode in [1, null]) {
          repository.handler = (command) {
            if (command.startsWith("printf '%s")) return _ok('/home/tester\n');
            return SshExecResult(
              exitCode: exitCode,
              stdout: '',
              stderr: 'denied',
              durationMs: 0,
            );
          };
          await expectLater(
            provider.uninstall('connection-1'),
            throwsStateError,
          );
          await expectLater(
            provider.stop('connection-1', sessionId: sessionId, pid: 4321),
            throwsStateError,
          );
        }
      },
    );

    test('preferred ports are stable and inside the configured range', () {
      final first = SshRemoteIdeProvider.preferredPortFor(hostKey);
      final second = SshRemoteIdeProvider.preferredPortFor(hostKey);
      final other = SshRemoteIdeProvider.preferredPortFor('another-host-key');

      expect(first, second);
      expect(first, inInclusiveRange(18090, 18189));
      expect(other, inInclusiveRange(18090, 18189));
    });

    test('launches code-server with the expected arguments', () async {
      repository.handler = _startHandler();

      final launch = await provider.start(
        'connection-1',
        sessionId: sessionId,
        hostKey: hostKey,
        version: version,
      );

      expect(launch.port, SshRemoteIdeProvider.preferredPortFor(hostKey));
      expect(launch.pid, 4321);
      expect(launch.version, version);
      expect(
        launch.sessionFile,
        '/home/tester/.local/share/hostdeck/code-server/$hostKey/'
        'sessions/$sessionId.json',
      );

      final launchCall = repository.calls.firstWhere(
        (call) => call.command.contains('IDE_PID'),
      );
      final command = launchCall.command;
      expect(command, contains('--auth'));
      expect(command, contains('--bind-addr'));
      expect(command, contains('127.0.0.1:${launch.port}'));
      expect(command, contains('--enable-remote-storage'));
      expect(command, contains('--disable-telemetry'));
      expect(command, contains('--disable-update-check'));
      expect(command, contains('--disable-workspace-trust'));
      expect(command, contains('--user-data-dir'));
      expect(command, contains('--extensions-dir'));
      expect(command, contains('--idle-timeout-seconds'));
      expect(command, contains('3600'));
      expect(command, contains('/logs/code-server.log'));
      expect(launchCall.timeout, isNotNull);

      final sessionFileCall = repository.calls.firstWhere(
        (call) =>
            call.command.startsWith('mkdir -p') &&
            call.command.contains('printf') &&
            call.command.contains('.json') &&
            call.command.contains(sessionId),
      );
      expect(sessionFileCall.command, contains('"pid":4321'));
      expect(sessionFileCall.command, contains('"hostKey":"$hostKey"'));
      expect(sessionFileCall.command, contains('"port":${launch.port}'));
      expect(sshService.closedSessionIds, isNotEmpty);
    });

    test('merges watcher excludes into remote user settings', () async {
      final base = _startHandler();
      var settingsWrite = '';
      repository.handler = (command) {
        if (command.startsWith('cat ') && command.contains('settings.json')) {
          return _ok(
            '{"editor.fontSize":14,"files.watcherExclude":{"**/custom/**":true}}${String.fromCharCode(10)}',
          );
        }
        if (command.contains('settings.json') &&
            command.startsWith("printf '%s'")) {
          settingsWrite = command;
          return _ok();
        }
        return base(command);
      };

      await provider.start(
        'connection-1',
        sessionId: sessionId,
        hostKey: hostKey,
        version: version,
      );

      expect(settingsWrite, isNotEmpty);
      expect(settingsWrite, contains('editor.fontSize'));
      expect(settingsWrite, contains('**/custom/**'));
      expect(settingsWrite, contains('**/.dart_tool/**'));
      expect(settingsWrite, contains('search.followSymlinks'));
    });

    test('retries the next port when the preferred one is listening', () async {
      final preferred = SshRemoteIdeProvider.preferredPortFor(hostKey);
      var listeningChecks = 0;
      repository.handler = (command) {
        if (command.startsWith("printf '%s")) return _ok('/home/tester\n');
        if (command.startsWith('ss -ltn')) {
          listeningChecks++;
          return listeningChecks == 1
              ? _ok(
                  'State Recv-Q Send-Q Local Address:Port Peer Address:Port '
                  'Process\n'
                  'LISTEN 0 128 127.0.0.1:$preferred 0.0.0.0:*\n',
                )
              : _ok();
        }
        if (command.startsWith('[ -x ')) return _ok();
        if (command.contains('--version')) return _ok('$version\n');
        if (command.contains('IDE_PID')) return _ok('IDE_PID:999\n');
        return _ok();
      };

      final launch = await provider.start(
        'connection-1',
        sessionId: sessionId,
        hostKey: hostKey,
        version: version,
      );

      expect(launch.port, preferred + 1);
      expect(launch.pid, 999);
    });

    test('rejects a version mismatch before launching', () async {
      repository.handler = (command) {
        if (command.startsWith("printf '%s")) return _ok('/home/tester\n');
        if (command.startsWith('[ -x ')) return _ok();
        if (command.contains('--version')) return _ok('4.0.0\n');
        return _ok();
      };

      await expectLater(
        provider.start(
          'connection-1',
          sessionId: sessionId,
          hostKey: hostKey,
          version: version,
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('版本不匹配'),
          ),
        ),
      );
      expect(
        repository.calls.any((call) => call.command.contains('IDE_PID')),
        isFalse,
      );
    });

    test(
      'stop kills the process and removes the recorded session file',
      () async {
        repository.handler = _startHandler();
        final launch = await provider.start(
          'connection-1',
          sessionId: sessionId,
          hostKey: hostKey,
          version: version,
        );
        repository.calls.clear();

        await provider.stop(
          'connection-1',
          sessionId: sessionId,
          pid: launch.pid,
        );

        final stopCall = repository.calls.firstWhere(
          (call) => call.command.contains('kill -TERM'),
        );
        expect(stopCall.command, contains('kill -KILL'));
        expect(stopCall.command, contains('rm -f'));
        expect(stopCall.command, contains(launch.sessionFile));
        expect(stopCall.timeout, isNotNull);
      },
    );

    test('stop without a recorded session file cleans up via glob', () async {
      repository.handler = _startHandler();

      await provider.stop('connection-1', sessionId: sessionId, pid: 4321);

      final stopCall = repository.calls.firstWhere(
        (call) => call.command.contains('kill -TERM'),
      );
      expect(stopCall.command, contains('/*/sessions/'));
      expect(stopCall.command, contains(sessionId));
    });

    test('rejects path traversal in the session id', () async {
      await expectLater(
        provider.stop('connection-1', sessionId: '../evil', pid: 1),
        throwsA(isA<ArgumentError>()),
      );
      expect(repository.calls, isEmpty);
    });

    test('derives the host key from SSH metadata when omitted', () async {
      sshService.metadata = const SshConnectionMetadata(
        host: 'example.com',
        port: 22,
        username: 'tester',
      );
      repository.handler = _startHandler();

      final launch = await provider.start(
        'connection-1',
        sessionId: sessionId,
        hostKey: '',
        version: version,
      );

      expect(
        launch.sessionFile,
        matches(
          RegExp(
            r'^/home/tester/\.local/share/hostdeck/code-server/[0-9a-f]{12}/',
          ),
        ),
      );
    });
  });

  group('LoopbackSshBridge', () {
    late ServerSocket echoServer;
    late StreamSubscription<Socket> echoSubscription;
    late _FakeSshService sshService;

    setUp(() async {
      echoServer = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      echoSubscription = echoServer.listen((socket) {
        socket.listen(
          socket.add,
          onDone: socket.destroy,
          onError: (Object _) => socket.destroy(),
        );
      });
      sshService = _FakeSshService();
    });

    tearDown(() async {
      await echoSubscription.cancel();
      await echoServer.close();
    });

    test('forwards local sockets to the remote port', () async {
      final client = _FakeEchoSshClient(echoServer.port);
      sshService.client = client;
      final bridge = await LoopbackSshBridge.start(
        sshService: sshService,
        connectionId: 'connection-1',
        remotePort: 18090,
      );

      expect(bridge.localPort, greaterThan(0));
      expect(bridge.isClosed, isFalse);

      final socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        bridge.localPort,
      );
      socket.add(utf8.encode('ping'));
      await socket.flush();
      final received = await socket.first;
      expect(utf8.decode(received), 'ping');

      await socket.close();
      await bridge.close();
      expect(bridge.isClosed, isTrue);
      expect(client.forwarded.single.remotePort, 18090);
      expect(client.forwarded.single.remoteHost, '127.0.0.1');

      await expectLater(
        Socket.connect(
          InternetAddress.loopbackIPv4,
          bridge.localPort,
          timeout: const Duration(seconds: 2),
        ),
        throwsA(isA<SocketException>()),
      );
    });

    test('close is idempotent', () async {
      final bridge = await LoopbackSshBridge.start(
        sshService: sshService..client = _FakeEchoSshClient(echoServer.port),
        connectionId: 'connection-1',
        remotePort: 18090,
      );

      await bridge.close();
      await bridge.close();

      expect(bridge.isClosed, isTrue);
    });

    test('rejects invalid ports and missing connections', () async {
      await expectLater(
        LoopbackSshBridge.start(
          sshService: sshService,
          connectionId: 'connection-1',
          remotePort: 0,
        ),
        throwsA(isA<ArgumentError>()),
      );

      await expectLater(
        LoopbackSshBridge.start(
          sshService: sshService,
          connectionId: 'missing',
          remotePort: 18090,
        ),
        throwsA(isA<StateError>()),
      );
    });
  });
}

_ExecHandler _preflightHandler({
  String arch = 'x86_64',
  String libc = 'glibc 2.31',
  String availableKb = '5000000',
  Set<String> tools = const {'tar', 'setsid', 'nohup', 'sha256sum'},
  String installedVersion = '',
}) {
  return (command) {
    if (command.startsWith("printf '%s")) return _ok('/home/tester\n');
    if (command == 'uname -m') return _ok('$arch\n');
    if (command.startsWith('getconf')) return _ok('$libc\n');
    if (command.startsWith('df -Pk')) {
      return _ok(
        'Filesystem 1024-blocks Used Available Capacity Mounted on\n'
        '/dev/sda1 100000000 1000 $availableKb 1% /home\n',
      );
    }
    if (command.startsWith('for tool in')) {
      final lines = <String>[];
      for (final tool in const ['tar', 'setsid', 'nohup', 'sha256sum']) {
        lines.add(tools.contains(tool) ? 'yes:$tool' : 'no:$tool');
      }
      return _ok('${lines.join('\n')}\n');
    }
    if (command.contains('bin/code-server')) {
      return _ok(installedVersion.isEmpty ? '' : '$installedVersion\n');
    }
    return _ok();
  };
}

_ExecHandler _installHandler(
  IdePackage package, {
  String? remoteSha256,
  String remoteVersion = '4.143.1',
}) {
  final expectedSha = remoteSha256 ?? package.sha256;
  return (command) {
    if (command.startsWith("printf '%s")) return _ok('/home/tester\n');
    if (command.startsWith('command -v sha256sum')) return _ok();
    if (command.startsWith('mkdir -p')) return _ok();
    if (command.startsWith('sha256sum ')) {
      return _ok('$expectedSha  /home/tester/archive.tar.gz\n');
    }
    if (command.contains('tar -xzf')) return _ok();
    if (command.contains('--version')) return _ok('$remoteVersion\n');
    return _ok();
  };
}

_ExecHandler _startHandler() {
  return (command) {
    if (command.startsWith("printf '%s")) return _ok('/home/tester\n');
    if (command.startsWith('ss -ltn')) return _ok();
    if (command.startsWith('[ -x ')) return _ok();
    if (command.contains('--version')) return _ok('4.143.1\n');
    if (command.contains('IDE_PID')) return _ok('IDE_PID:4321\n');
    return _ok();
  };
}

Future<IdePackage> _createPackage(
  Directory dir, {
  String version = '4.143.1',
  String arch = 'amd64',
  String sha256 = 'abc123',
}) async {
  final content = _archiveBytes();
  final file = File('${dir.path}/$version-linux-$arch.tar.gz');
  await file.writeAsBytes(content, flush: true);
  return IdePackage(
    id: IdePackage.buildId(version: version, arch: arch),
    version: version,
    arch: arch,
    path: file.path,
    size: content.length,
    sha256: sha256,
    createdAt: DateTime.now(),
  );
}

List<int> _archiveBytes() => utf8.encode('fake-code-server-archive');

SshExecResult _ok([String stdout = '']) =>
    SshExecResult(exitCode: 0, stdout: stdout, stderr: '', durationMs: 0);

class _RecordedExec {
  const _RecordedExec({
    required this.command,
    required this.timeout,
    required this.login,
  });

  final String command;
  final Duration? timeout;
  final bool login;
}

class _FakeSshRepository extends SshRepository {
  _FakeSshRepository(this.handler);

  _ExecHandler handler;
  final List<_RecordedExec> calls = [];
  String? uploadedPath;
  List<int>? uploadedBytes;
  int uploadChunks = 0;

  @override
  Future<SshExecResult> execWithResult(
    SshOperationContext session,
    String command, {
    String? cwd,
    Duration? timeout,
    String? stdin,
    int? maxOutputBytes,
    bool login = true,
    Future<void>? cancellation,
    bool Function()? isCancelled,
  }) async {
    calls.add(_RecordedExec(command: command, timeout: timeout, login: login));
    return handler(command);
  }

  @override
  Future<void> writeFileStream(
    SshSession session,
    String path,
    Stream<List<int>> content,
  ) async {
    uploadedPath = path;
    final builder = BytesBuilder(copy: true);
    await for (final chunk in content) {
      uploadChunks++;
      builder.add(chunk);
    }
    uploadedBytes = builder.takeBytes();
  }
}

class _FakeSshService extends SshService {
  SshConnectionMetadata? metadata;
  SSHClient? client;
  final List<SshSessionPurpose> purposes = [];
  final List<String> closedSessionIds = [];
  int _nextSessionId = 0;

  @override
  Future<SshSession> createSftpSession(
    String connectionId, {
    required SshSessionPurpose purpose,
  }) async {
    purposes.add(purpose);
    return _FakeSshSession(
      connectionId: connectionId,
      id: 'ssh-${_nextSessionId++}',
    );
  }

  @override
  Future<void> closeSession(String id) async {
    closedSessionIds.add(id);
  }

  @override
  SshConnectionMetadata? metadataFor(String connectionId) => metadata;

  @override
  SSHClient? getClient(String connectionId) => client;
}

class _FakeSshSession implements SshSession {
  _FakeSshSession({required this.connectionId, required this.id});

  @override
  final String connectionId;
  @override
  final String id;

  @override
  final SshOperationLimiter operationLimiter = SshOperationLimiter(
    maxConcurrentOperations: 4,
  );

  @override
  SSHClient get client => throw UnimplementedError();

  @override
  SSHSession? get shell => null;

  @override
  Stream<String> get output => const Stream.empty();

  @override
  StreamController<String> get outputController =>
      StreamController<String>.broadcast();

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

class _FakeEchoSshClient implements SSHClient {
  _FakeEchoSshClient(this.echoPort);

  final int echoPort;
  final List<({String remoteHost, int remotePort})> forwarded = [];
  final Completer<void> _done = Completer<void>();

  @override
  Future<SSHForwardChannel> forwardLocal(
    String remoteHost,
    int remotePort, {
    String localHost = 'localhost',
    int localPort = 0,
  }) async {
    forwarded.add((remoteHost: remoteHost, remotePort: remotePort));
    final socket = await Socket.connect(InternetAddress.loopbackIPv4, echoPort);
    return _SocketForwardChannel(socket);
  }

  @override
  Future<void> get done => _done.future;

  @override
  bool get isClosed => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SocketForwardChannel implements SSHForwardChannel {
  _SocketForwardChannel(this._socket);

  final Socket _socket;

  @override
  Stream<Uint8List> get stream => _socket;

  @override
  StreamSink<List<int>> get sink => _socket;

  @override
  Future<void> get done => _socket.done;

  @override
  Future<void> flush() => _socket.flush();

  @override
  Future<void> close() async {
    await _socket.close();
  }

  @override
  void destroy() => _socket.destroy();
}
