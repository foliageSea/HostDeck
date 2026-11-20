import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:host_deck/server/core/ssh/ssh_connection_handle.dart';
import 'package:host_deck/server/core/ssh/ssh_repository.dart';
import 'package:host_deck/server/core/ssh/ssh_session.dart';
import 'package:host_deck/server/features/files/file_sidecar_executor.dart';
import 'package:host_deck_sidecar/protocol.dart';
import 'package:path/path.dart' as p;

void main() {
  late _Fixture fixture;

  setUp(() async {
    fixture = await _Fixture.create();
  });
  tearDown(() async => fixture.dispose());

  test(
    'deploys once, verifies before rename, and passes paths only on stdin',
    () async {
      const source = "a/link/../say 'hello' 雪\n\$(touch never)";
      const target = '/other/target; echo unexpected';
      final progress = <SidecarProgress>[];
      final process = fixture.queueProcess((process, frame) {
        expect(frame, {
          'v': 1,
          'id': 'id1',
          'type': 'run',
          'operation': 'copy',
          'sourcePath': '$_home/$source',
          'targetPath': target,
        });
        process.emit('started', const {}, 5);
        process.emit('progress', {
          'progress': const SidecarProgress(
            phase: SidecarPhase.working,
            bytesDone: 3,
            bytesTotal: 4,
            entriesDone: 1,
            entriesTotal: 2,
          ).toJson(),
        });
        process.emit('result', {'status': 'success'});
      });
      final result = await fixture.run(
        source: source,
        target: target,
        progress: progress.add,
      );
      expect(result?.cancelled, false);
      expect(progress.map((p) => p.phase), [
        SidecarPhase.deploying,
        SidecarPhase.working,
      ]);
      expect(progress.last.bytesDone, 3);
      expect(fixture.client.commands.single, isNot(contains('touch never')));
      expect(
        fixture.client.commands.single,
        isNot(contains('echo unexpected')),
      );
      expect(fixture.client.commands.single, contains('run --stdio'));
      expect(fixture.sftp.entries[fixture.artifactPath]?.permissions, 0x1c0);
      expect(fixture.sftp.stagingPaths, isEmpty);
      expect(fixture.sftp.writes, 1);
      expect(fixture.events, [
        'probe',
        'mkdir-stage',
        'write',
        'hash',
        'version',
        'publish',
        'cleanup-stage',
        'run',
      ]);
      expect(process.terms, 0);
      expect(process.closed, true);
      expect(fixture.session.operationLimiter.runningOperations, 0);

      fixture.queueSuccess();
      expect((await fixture.run())?.cancelled, false);
      expect(fixture.sftp.writes, 1);
      expect(fixture.events.where((event) => event == 'hash'), hasLength(2));
    },
  );

  test(
    'concurrent callers on the same SSH client share in-flight deployment',
    () async {
      final probeGate = Completer<void>();
      fixture.repository.probeGate = probeGate;
      fixture.queueSuccess();
      fixture.queueSuccess();
      final first = fixture.run();
      final second = fixture.run(id: 'id2', session: fixture.newSession());
      await fixture.repository.probed.future;
      probeGate.complete();
      expect((await Future.wait([first, second])).map((r) => r?.cancelled), [
        false,
        false,
      ]);
      expect(fixture.events.where((event) => event == 'probe'), hasLength(1));
      expect(fixture.sftp.writes, 1);
      expect(fixture.client.commands, hasLength(2));
    },
  );

  test(
    'cancelled deployment waiter cannot replay or interrupt another caller',
    () async {
      final probeGate = Completer<void>();
      final cancellation = Completer<void>();
      fixture.repository.probeGate = probeGate;
      fixture.queueSuccess();
      final first = fixture.run(cancellation: cancellation.future);
      await fixture.repository.probed.future;
      final second = fixture.run(id: 'id2', session: fixture.newSession());
      cancellation.complete();
      expect((await first)?.cancelled, true);
      expect(fixture.client.commands, isEmpty);
      probeGate.complete();
      expect((await second)?.cancelled, false);
      expect(fixture.client.commands, hasLength(1));
      expect(fixture.events.where((event) => event == 'probe'), hasLength(1));
    },
  );

  test('disabled or unsupported format does not touch SSH', () async {
    expect(
      await fixture.run(executor: fixture.executor(enabled: false)),
      isNull,
    );
    expect(
      await fixture.run(
        operation: SidecarOperation.extract,
        source: '/input.tar.xz',
      ),
      isNull,
    );
    expect(
      await fixture.run(
        operation: SidecarOperation.compress,
        target: '/output.tar',
      ),
      isNull,
    );
    expect(fixture.events, isEmpty);
    expect(fixture.client.commands, isEmpty);
  });

  test('absent package and incompatible target are legacy-eligible', () async {
    await fixture.manifest.delete();
    expect(await fixture.run(), isNull);
    expect(fixture.events, isEmpty);
    await fixture.writeManifest();
    fixture.repository.probeOutput = 'Linux\nx86_64\nglibc 2.34\n1000\n';
    expect(await fixture.run(), isNull);
    expect(fixture.sftp.writes, 0);
    expect(fixture.client.commands, isEmpty);
  });

  test('extracts uncompressed TAR on supported arm64', () async {
    fixture.repository.probeOutput = 'Linux\naarch64\nglibc 2.36\n1000\n';
    fixture.queueSuccess();
    final result = await fixture.run(
      operation: SidecarOperation.extract,
      source: '/in.TAR',
    );
    expect(result?.cancelled, false);
    expect(
      fixture.client.commands.single,
      contains('hostdeck-file-sidecar-linux-arm64'),
    );
  });

  test('local artifact mismatch fails closed before opening SFTP', () async {
    await File(p.join(fixture.directory.path, _amd64)).writeAsBytes([5, 5, 5]);
    await expectLater(
      fixture.run(),
      throwsA(_failure('integrity_check_failed')),
    );
    expect(fixture.client.sftpOpens, 0);
    expect(fixture.client.commands, isEmpty);
  });

  test(
    'deployment timeout cleans stage and does not open a task channel',
    () async {
      final writeGate = Completer<void>();
      fixture.sftp.writeGate = writeGate;
      await expectLater(
        fixture.run(
          executor: fixture.executor(
            deployment: const Duration(milliseconds: 80),
          ),
        ),
        throwsA(_failure('deployment_timeout')),
      );
      expect(fixture.sftp.writes, 1);
      expect(fixture.sftp.stagingPaths, isEmpty);
      expect(fixture.sftp.entries[fixture.artifactPath], isNull);
      expect(fixture.client.commands, isEmpty);
      writeGate.complete();
    },
  );

  for (final parent in ['.local', '.local/lib', '.local/lib/hostdeck']) {
    test(
      'an owned group-writable $parent uses a separate private cache',
      () async {
        final segments = parent.split('/');
        var path = _home;
        for (final (index, segment) in segments.indexed) {
          path = '$path/$segment';
          fixture.sftp.entries[path] = _Entry(
            directory: true,
            permissions: index == segments.length - 1 ? 0x1fd : 0x1ed,
          );
        }
        const cache = '$_home/.hostdeck-file-sidecar';
        final installed = '$cache/$_hash/$_amd64';
        fixture.queueSuccess();
        expect((await fixture.run())?.cancelled, false);
        expect(
          fixture.client.commands.single,
          contains('.hostdeck-file-sidecar/$_hash/$_amd64'),
        );
        expect(fixture.sftp.entries[cache]?.permissions, 0x1c0);
        expect(fixture.sftp.entries['$cache/$_hash']?.permissions, 0x1c0);
        expect(fixture.sftp.entries[installed]?.permissions, 0x1c0);
        expect(fixture.sftp.entries[path]?.permissions, 0x1fd);
        expect(
          fixture.sftp.entries.keys.where(
            (entry) => entry.startsWith('$path/'),
          ),
          isEmpty,
        );
        expect(fixture.sftp.stagingPaths, isEmpty);
        fixture.queueSuccess();
        expect((await fixture.run())?.cancelled, false);
        expect(fixture.sftp.writes, 1);
      },
    );
  }

  test(
    'world-writable, foreign or non-directory parents do not fall back',
    () async {
      for (final entry in [
        _Entry(directory: true, permissions: 0x1ff),
        _Entry(directory: true, permissions: 0x1fd, owner: 1001),
        _Entry(directory: false, permissions: 0x1fd),
      ]) {
        fixture.sftp.entries['$_home/.local'] = entry;
        await expectLater(
          fixture.run(),
          throwsA(_failure('integrity_check_failed')),
        );
      }
      expect(fixture.sftp.entries['$_home/.hostdeck-file-sidecar'], isNull);
      expect(fixture.client.commands, isEmpty);
    },
  );

  test(
    'a writable home or incorrectly protected private cache is refused',
    () async {
      fixture.sftp.entries[_home] = _Entry(directory: true, permissions: 0x1fd);
      await expectLater(
        fixture.run(),
        throwsA(_failure('integrity_check_failed')),
      );
      fixture.sftp.entries[_home] = _Entry(directory: true, permissions: 0x1e8);
      fixture.sftp.entries['$_home/.local'] = _Entry(
        directory: true,
        permissions: 0x1fd,
      );
      const cache = '$_home/.hostdeck-file-sidecar';
      fixture.sftp.entries[cache] = _Entry(directory: true, permissions: 0x1ed);
      await expectLater(
        fixture.run(),
        throwsA(_failure('integrity_check_failed')),
      );
      fixture.sftp.entries[cache] = _Entry(directory: true, permissions: 0x1c0);
      fixture.sftp.entries['$cache/$_hash'] = _Entry(
        directory: true,
        permissions: 0x1ed,
      );
      await expectLater(
        fixture.run(),
        throwsA(_failure('integrity_check_failed')),
      );
      expect(fixture.sftp.writes, 0);
      expect(fixture.client.commands, isEmpty);
    },
  );

  test('a symlink in the cached install directory is refused', () async {
    fixture.sftp.entries['$_home/.local'] = _Entry(
      directory: true,
      permissions: 0x1c0,
      symlink: true,
    );
    await expectLater(
      fixture.run(),
      throwsA(_failure('integrity_check_failed')),
    );
    expect(fixture.sftp.writes, 0);
    expect(fixture.client.commands, isEmpty);
  });

  test('invalid manifest protocol is not benign absence', () async {
    await fixture.writeManifest(protocol: 2);
    await expectLater(
      fixture.run(),
      throwsA(_failure('integrity_check_failed')),
    );
    expect(fixture.events, isEmpty);
  });

  for (final check in ['hash', 'version', 'mode']) {
    test(
      'remote $check mismatch is fatal and cleans staging before return',
      () async {
        if (check == 'hash') fixture.repository.invalidHash = true;
        if (check == 'version') fixture.repository.version = 'unexpected';
        if (check == 'mode') fixture.sftp.ignoreFileMode = true;
        await expectLater(
          fixture.run(),
          throwsA(_failure('integrity_check_failed')),
        );
        expect(fixture.sftp.entries[fixture.artifactPath], isNull);
        expect(fixture.sftp.stagingPaths, isEmpty);
        expect(fixture.events, isNot(contains('publish')));
        expect(fixture.client.commands, isEmpty);
      },
    );
  }

  test(
    'reused helper is revalidated and cannot be silently repaired',
    () async {
      fixture.queueSuccess();
      expect((await fixture.run())?.cancelled, false);
      fixture.sftp.entries[fixture.artifactPath]!.bytes = Uint8List.fromList([
        8,
        8,
        8,
      ]);
      await expectLater(
        fixture.run(),
        throwsA(_failure('integrity_check_failed')),
      );
      expect(fixture.sftp.writes, 1);
      expect(fixture.client.commands, hasLength(1));
    },
  );

  test('explicit exec channel rejection before run permits legacy', () async {
    fixture.client.rejectExec = true;
    expect(await fixture.run(), isNull);
    expect(fixture.session.operationLimiter.runningOperations, 0);
  });

  test(
    'EOF after a submitted run but before started is never replayable',
    () async {
      final process = fixture.queueProcess(
        (process, frame) => process.endOutput(),
      );
      await expectLater(fixture.run(), throwsA(_failure('connection_lost')));
      expect(process.terms, 1);
      expect(process.closed, true);
      expect(fixture.client.commands, hasLength(1));
    },
  );

  test(
    'requires matching SSH exit status before accepting a terminal frame',
    () async {
      for (final exitCode in <int?>[1, null]) {
        final process = fixture.queueProcess((process, frame) {
          process.emit('started');
          process.emit('result', {'status': 'success'});
          process.finish(exitCode);
        })..autoExit = false;
        await expectLater(fixture.run(), throwsA(_failure('exit_unconfirmed')));
        expect(process.closed, true);
      }
    },
  );

  test(
    'rejects a duplicate result even if the SSH exit status is zero',
    () async {
      final process = fixture.queueProcess((process, frame) {
        process.emit('started');
        process.emit('result', {'status': 'success'});
        process.emit('result', {'status': 'success'});
        process.finish(0);
      });
      process.autoExit = false;
      await expectLater(fixture.run(), throwsA(_failure('protocol_error')));
    },
  );

  test(
    'worker reports failure rather than fallback even for unsupported format',
    () async {
      final process = fixture.queueProcess((process, frame) {
        process.emit('started');
        process.emit('result', {
          'status': 'failed',
          'errorCode': 'unsupported_format',
          'message': 'not handled',
        });
      });
      await expectLater(fixture.run(), throwsA(_failure('unsupported_format')));
      expect(process.terms, 0);
    },
  );

  for (final invalid in [
    'wrong version',
    'wrong id',
    'oversized',
    'invalid progress',
  ]) {
    test('rejects $invalid responses without replaying', () async {
      final process = fixture.queueProcess((process, frame) {
        switch (invalid) {
          case 'wrong version':
            process.emit('started', {'v': 5});
          case 'wrong id':
            process.emit('started', {'id': 'unknown'});
          case 'oversized':
            process.stdoutController.add(Uint8List(sidecarMaxFrameBytes + 1));
          case 'invalid progress':
            process.emit('started');
            process.emit('progress', {
              'progress': {'phase': 'working', 'bytesDone': -1},
            });
        }
      });
      await expectLater(fixture.run(), throwsA(_failure('protocol_error')));
      expect(process.terms, 1);
      expect(fixture.client.commands, hasLength(1));
    });
  }

  test('missed started deadline fails rather than replaying', () async {
    final process = fixture.queueProcess((_, _) {});
    await expectLater(
      fixture.run(
        executor: fixture.executor(start: const Duration(milliseconds: 40)),
      ),
      throwsA(_failure('start_timeout')),
    );
    expect(process.terms, 1);
  });

  test('keeps stdin open for ping and stops after verified result', () async {
    final process = fixture.queueProcess((process, frame) {
      switch (frame['type']) {
        case 'run':
          process.emit('started');
        case 'ping':
          process.emit('heartbeat');
          process.emit('result', {'status': 'success'});
      }
    });
    expect((await fixture.run())?.cancelled, false);
    expect(process.inputs.map((frame) => frame['type']), ['run', 'ping']);
  });

  test('missing heartbeat after started fails without replay', () async {
    final process = fixture.queueProcess((process, frame) {
      if (frame['type'] == 'run') process.emit('started');
    });
    await expectLater(
      fixture.run(
        executor: fixture.executor(heartbeat: const Duration(milliseconds: 80)),
      ),
      throwsA(_failure('heartbeat_timeout')),
    );
    expect(process.inputs.map((frame) => frame['type']), contains('ping'));
    expect(process.terms, 1);
  });

  test(
    'cancel waits for authoritative cancelled result and drains progress',
    () async {
      final cancellation = Completer<void>();
      final progress = <SidecarProgress>[];
      final process = fixture.queueProcess((process, frame) {
        switch (frame['type']) {
          case 'run':
            process.emit('started');
            cancellation.complete();
          case 'cancel':
            expect(process.closed, false);
            process.emit('progress', {
              'progress': const SidecarProgress(
                phase: SidecarPhase.working,
                bytesDone: 8,
              ).toJson(),
            });
            process.emit('result', {'status': 'cancelled'});
        }
      });
      final result = await fixture.run(
        cancellation: cancellation.future,
        progress: progress.add,
      );
      expect(result?.cancelled, true);
      expect(progress.last.bytesDone, 8);
      expect(process.inputs.map((frame) => frame['type']), ['run', 'cancel']);
      expect(process.terms, 0);
    },
  );

  test('successful commit wins a cancellation race', () async {
    final cancellation = Completer<void>();
    fixture.queueProcess((process, frame) {
      switch (frame['type']) {
        case 'run':
          process.emit('started');
          cancellation.complete();
        case 'cancel':
          process.emit('result', {'status': 'success'});
      }
    });
    expect(
      (await fixture.run(cancellation: cancellation.future))?.cancelled,
      false,
    );
  });

  test(
    'cancel without acknowledgment sends TERM and closes, never reporting success',
    () async {
      final cancellation = Completer<void>();
      final process = fixture.queueProcess((process, frame) {
        if (frame['type'] == 'run') {
          process.emit('started');
          cancellation.complete();
        }
      });
      await expectLater(
        fixture.run(cancellation: cancellation.future),
        throwsA(_failure('cancel_unconfirmed')),
      );
      expect(process.inputs.map((frame) => frame['type']), ['run', 'cancel']);
      expect(process.terms, 1);
      expect(process.closed, true);
    },
  );

  test(
    'late SSH process after cancel is closed without receiving a run frame',
    () async {
      final cancellation = Completer<void>();
      fixture.client.openGate = Completer<void>();
      final process = fixture.queueSuccess();
      final outcome = fixture.run(cancellation: cancellation.future);
      await fixture.client.opened.future;
      cancellation.complete();
      expect((await outcome)?.cancelled, true);
      fixture.client.openGate!.complete();
      await process.closeDone.future;
      expect(process.inputs, isEmpty);
      expect(process.terms, 0);
      expect(fixture.session.operationLimiter.runningOperations, 0);
    },
  );
}

Matcher _failure(String code) =>
    isA<FileSidecarException>().having((error) => error.code, 'code', code);

const _home = "/home/side 'car";
const _amd64 = 'hostdeck-file-sidecar-linux-amd64';
const _arm64 = 'hostdeck-file-sidecar-linux-arm64';
const _artifact = [1, 2, 3];
const _version = 'v1.2.3';
final _hash = sha256.convert(_artifact).toString();

class _Fixture {
  final Directory directory;
  final events = <String>[];
  late final sftp = _FakeSftp(events);
  late final client = _FakeClient(sftp, events);
  late final repository = _FakeRepository(sftp, events);
  late final session = newSession();
  late final _defaultExecutor = executor();
  final _processes = <_FakeProcess>[];

  _Fixture(this.directory);

  static Future<_Fixture> create() async {
    final fixture = _Fixture(
      await Directory.systemTemp.createTemp('hostdeck-sidecar-test-'),
    );
    await File(p.join(fixture.directory.path, _amd64)).writeAsBytes(_artifact);
    await File(p.join(fixture.directory.path, _arm64)).writeAsBytes(_artifact);
    await fixture.writeManifest();
    return fixture;
  }

  Future<void> dispose() async {
    for (final process in _processes) {
      process.close();
    }
    await directory.delete(recursive: true);
  }

  SshSession newSession() =>
      SshSession(id: 'test', connectionId: 'connection', client: client);

  SshFileSidecarExecutor executor({
    bool enabled = true,
    Duration start = const Duration(seconds: 2),
    Duration heartbeat = const Duration(seconds: 2),
    Duration deployment = const Duration(seconds: 2),
  }) => SshFileSidecarExecutor(
    repository,
    enabled: enabled,
    sidecarDirectory: directory.path,
    startTimeout: start,
    deploymentTimeout: deployment,
    pingInterval: const Duration(milliseconds: 25),
    heartbeatTimeout: heartbeat,
    cancelGrace: const Duration(milliseconds: 35),
    terminationGrace: const Duration(milliseconds: 35),
  );

  String get artifactPath =>
      '$_home/.local/lib/hostdeck/file-sidecar/$_hash/$_amd64';
  File get manifest => File(p.join(directory.path, 'manifest.json'));

  Future<void> writeManifest({
    int protocol = 1,
  }) async => manifest.writeAsString(
    jsonEncode({
      'protocol': protocol,
      'version': _version,
      'artifacts': {
        'amd64': {'file': _amd64, 'size': _artifact.length, 'sha256': _hash},
        'arm64': {'file': _arm64, 'size': _artifact.length, 'sha256': _hash},
      },
    }),
  );

  _FakeProcess queueProcess(
    void Function(_FakeProcess, Map<String, dynamic>) respond,
  ) {
    final process = _FakeProcess(respond);
    _processes.add(process);
    client.queue.add(process);
    return process;
  }

  _FakeProcess queueSuccess() => queueProcess((process, frame) {
    process.emit('started');
    process.emit('result', {'status': 'success'});
  });

  Future<FileSidecarResult?> run({
    String id = 'id1',
    String source = '/source',
    String target = '/target',
    SidecarOperation operation = SidecarOperation.copy,
    Future<void>? cancellation,
    void Function(SidecarProgress)? progress,
    SshFileSidecarExecutor? executor,
    SshSession? session,
  }) => (executor ?? _defaultExecutor).run(
    session ?? this.session,
    id: id,
    operation: operation,
    sourcePath: source,
    targetPath: target,
    onProgress: progress ?? (_) {},
    cancellation: cancellation ?? Completer<void>().future,
    isCancelled: () => false,
  );
}

class _FakeRepository extends SshRepository {
  final _FakeSftp sftp;
  final List<String> events;
  String probeOutput = 'Linux\nx86_64\nglibc 2.35\n1000\n';
  bool invalidHash = false;
  String version = _version;
  final probed = Completer<void>();
  Completer<void>? probeGate;

  _FakeRepository(this.sftp, this.events);

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
    expect(login, false);
    expect(maxOutputBytes, 4096);
    String output;
    if (command.contains('getconf GNU_LIBC_VERSION')) {
      events.add('probe');
      if (!probed.isCompleted) probed.complete();
      await probeGate?.future;
      output = probeOutput;
    } else if (command.startsWith('LC_ALL=C sha256sum < ')) {
      events.add('hash');
      final staged = command.contains('.upload-');
      final path = sftp.entries.keys.singleWhere(
        (path) =>
            path.endsWith(command.contains(_arm64) ? _arm64 : _amd64) &&
            path.contains('.upload-') == staged,
      );
      final hash = invalidHash
          ? 'wrong'
          : sha256.convert(sftp.entries[path]!.bytes!);
      output = '$hash  -\n';
    } else {
      expect(command, endsWith('--version --json'));
      events.add('version');
      output = jsonEncode({'protocol': 1, 'version': version});
    }
    return SshExecResult(
      exitCode: 0,
      stdout: output,
      stderr: '',
      durationMs: 0,
    );
  }
}

class _Entry {
  final bool directory;
  int permissions;
  Uint8List? bytes;
  final bool symlink;
  final int owner;

  _Entry({
    required this.directory,
    required this.permissions,
    this.symlink = false,
    this.owner = 1000,
  });
}

class _FakeSftp implements SftpClient {
  final List<String> events;
  final entries = <String, _Entry>{
    _home: _Entry(directory: true, permissions: 0x1ed),
  };
  int writes = 0;
  bool ignoreFileMode = false;
  Completer<void>? writeGate;

  _FakeSftp(this.events);

  Iterable<String> get stagingPaths =>
      entries.keys.where((path) => path.contains('.upload-'));

  @override
  Future<String> absolute(String path) async {
    expect(path, '.');
    return _home;
  }

  @override
  Future<SftpFileAttrs> stat(String path, {bool followLink = true}) async {
    expect(followLink, false);
    final entry = entries[path];
    if (entry == null) {
      throw SftpStatusError(SftpStatusCode.noSuchFile, 'missing');
    }
    return SftpFileAttrs(
      userID: entry.owner,
      size: entry.bytes?.length,
      mode: SftpFileMode.value(
        (entry.symlink
                ? 0xa000
                : entry.directory
                ? 0x4000
                : 0x8000) |
            entry.permissions,
      ),
    );
  }

  @override
  Future<void> mkdir(String path, [SftpFileAttrs? attrs]) async {
    expect(entries, isNot(contains(path)));
    expect(attrs?.mode?.value, 0x1c0);
    entries[path] = _Entry(directory: true, permissions: attrs!.mode!.value);
    if (path.contains('.upload-')) events.add('mkdir-stage');
  }

  @override
  Future<SftpFile> open(
    String path, {
    SftpFileOpenMode mode = SftpFileOpenMode.read,
  }) async {
    expect(entries, isNot(contains(path)));
    expect(mode.flag & SftpFileOpenMode.exclusive.flag, isNot(0));
    expect(entries[p.posix.dirname(path)]?.permissions, 0x1c0);
    final entry = entries[path] = _Entry(directory: false, permissions: 0x1a4);
    return _FakeFile(this, entry);
  }

  @override
  Future<void> rename(String oldPath, String newPath) async {
    expect(oldPath, contains('.upload-'));
    expect(newPath, isNot(contains('.upload-')));
    expect(events.last, 'version');
    events.add('publish');
    entries[newPath] = entries.remove(oldPath)!;
  }

  @override
  Future<void> remove(String filename) async => entries.remove(filename);

  @override
  Future<void> rmdir(String dirname) async {
    entries.remove(dirname);
    events.add('cleanup-stage');
  }

  @override
  Future<void> close() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeFile implements SftpFile {
  final _FakeSftp sftp;
  final _Entry entry;

  _FakeFile(this.sftp, this.entry);

  @override
  Future<void> setStat(SftpFileAttrs attrs) async {
    if (!sftp.ignoreFileMode) entry.permissions = attrs.mode!.value;
  }

  @override
  Future<void> writeBytes(
    Uint8List data, {
    int offset = 0,
    int chunkSize = 0,
    int maxPendingRequests = 0,
  }) async {
    sftp.writes++;
    sftp.events.add('write');
    entry.bytes = Uint8List.fromList(data);
    await sftp.writeGate?.future;
  }

  @override
  Future<void> close() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeClient implements SSHClient {
  final _FakeSftp filesystem;
  final List<String> events;
  final queue = <_FakeProcess>[];
  final commands = <String>[];
  final opened = Completer<void>();
  Completer<void>? openGate;
  bool rejectExec = false;
  int sftpOpens = 0;

  _FakeClient(this.filesystem, this.events);

  @override
  Future<SftpClient> sftp() async {
    sftpOpens++;
    return filesystem;
  }

  @override
  Future<SSHSession> execute(
    String command, {
    SSHPtyConfig? pty,
    SSHX11Config? x11,
    Map<String, String>? environment,
  }) async {
    expect(pty, isNull);
    events.add('run');
    commands.add(command);
    if (!opened.isCompleted) opened.complete();
    if (rejectExec) throw SSHChannelRequestError('exec refused');
    await openGate?.future;
    return queue.removeAt(0);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeProcess implements SSHSession {
  final stdoutController = StreamController<Uint8List>();
  final stderrController = StreamController<Uint8List>();
  final stdinController = StreamController<Uint8List>();
  final closeDone = Completer<void>();
  final inputs = <Map<String, dynamic>>[];
  bool closed = false;
  bool autoExit = true;
  int? _exitCode;
  int terms = 0;
  String? _id;

  _FakeProcess(void Function(_FakeProcess, Map<String, dynamic>) respond) {
    decodeSidecarFrames(stdinController.stream).listen((frame) {
      _id ??= frame['id'] as String;
      inputs.add(frame);
      respond(this, frame);
    });
  }

  void emit(
    String type, [
    Map<String, Object?> fields = const {},
    int? splitAt,
  ]) {
    final encoded = encodeSidecarFrame({
      'v': 1,
      'id': _id,
      'type': type,
      ...fields,
    });
    if (splitAt == null) {
      stdoutController.add(encoded);
    } else {
      stdoutController.add(encoded.sublist(0, splitAt));
      stdoutController.add(encoded.sublist(splitAt));
    }
    if (type == 'result' && autoExit) {
      final code = switch (fields['status']) {
        'success' => 0,
        'cancelled' => 130,
        _ => 1,
      };
      scheduleMicrotask(() => finish(code));
    }
  }

  void finish(int? code) {
    _exitCode = code;
    close();
  }

  void endOutput() => unawaited(stdoutController.close());

  @override
  void close() {
    if (closed) return;
    closed = true;
    unawaited(stdinController.close());
    unawaited(stdoutController.close());
    unawaited(stderrController.close());
    closeDone.complete();
  }

  @override
  Future<void> flush() async =>
      fail('Do not flush the shared SSH socket for a heartbeat');

  @override
  void kill(SSHSignal signal) {
    expect(signal, SSHSignal.TERM);
    terms++;
  }

  @override
  int? get exitCode => _exitCode;
  @override
  SSHSessionExitSignal? get exitSignal => null;
  @override
  Future<void> get done => closeDone.future;
  @override
  StreamSink<Uint8List> get stdin => stdinController.sink;
  @override
  Stream<Uint8List> get stderr => stderrController.stream;
  @override
  Stream<Uint8List> get stdout => stdoutController.stream;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
