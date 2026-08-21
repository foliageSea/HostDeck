import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dartssh2/dartssh2.dart';

import 'package:host_deck/server/core/ssh/ssh_session.dart';
import 'package:host_deck/server/features/files/file_item.dart';

class SshExecResult {
  final int? exitCode;
  final String stdout;
  final String stderr;
  final int durationMs;

  const SshExecResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    required this.durationMs,
  });

  Map<String, dynamic> toJson() => {
    'exitCode': exitCode,
    'stdout': stdout,
    'stderr': stderr,
    'durationMs': durationMs,
  };
}

enum SshExecStreamSource { stdout, stderr }

class SshExecStreamEvent {
  final SshExecStreamSource? source;
  final String text;
  final int? exitCode;
  final bool completed;

  const SshExecStreamEvent.output(this.source, this.text)
    : exitCode = null,
      completed = false;

  const SshExecStreamEvent.completed(this.exitCode)
    : source = null,
      text = '',
      completed = true;
}

class SshRepository {
  String _shellQuote(String value) {
    return "'${value.replaceAll("'", "'\\''")}'";
  }

  Future<void> _runCheckedShellCommand(
    SshSession session,
    String command,
  ) async {
    final result = await session.runOperation(
      () => session.client.runWithResult('sh -lc ${_shellQuote(command)}'),
    );
    final stdout = utf8.decode(result.stdout).trim();
    final stderr = utf8.decode(result.stderr).trim();
    final output = [
      stderr,
      stdout,
    ].where((value) => value.isNotEmpty).join('\n');

    if (result.exitCode != null && result.exitCode != 0) {
      throw Exception(
        output.isNotEmpty
            ? output
            : 'Command failed with exit code ${result.exitCode}.',
      );
    }
  }

  Future<String> exec(SshSession session, String command) async {
    final result = await execBytes(session, command);
    return utf8.decode(result);
  }

  Future<Uint8List> execBytes(SshSession session, String command) async {
    final result = await session.runOperation(
      () => session.client.run(command),
    );
    return result;
  }

  Future<SshExecResult> execWithResult(
    SshSession session,
    String command, {
    String? cwd,
    Duration? timeout,
    String? stdin,
  }) async {
    final stopwatch = Stopwatch()..start();
    final script = cwd == null || cwd.trim().isEmpty
        ? command
        : 'cd ${_shellQuote(cwd)} && $command';
    SSHSession? sshSession;

    try {
      final result = await session
          .runOperation(() async {
            sshSession = await session.client.execute(
              'sh -lc ${_shellQuote(script)}',
            );

            if (stdin != null) {
              sshSession!.stdin.add(Uint8List.fromList(utf8.encode(stdin)));
            }
            await sshSession!.stdin.close();

            final stdoutBuilder = BytesBuilder(copy: false);
            final stderrBuilder = BytesBuilder(copy: false);
            final stdoutDone = Completer<void>();
            final stderrDone = Completer<void>();

            sshSession!.stdout.listen(
              stdoutBuilder.add,
              onDone: stdoutDone.complete,
              onError: stdoutDone.completeError,
            );
            sshSession!.stderr.listen(
              stderrBuilder.add,
              onDone: stderrDone.complete,
              onError: stderrDone.completeError,
            );

            await stdoutDone.future;
            await stderrDone.future;
            await sshSession!.done;

            return SshExecResult(
              exitCode: sshSession!.exitCode,
              stdout: utf8.decode(
                stdoutBuilder.takeBytes(),
                allowMalformed: true,
              ),
              stderr: utf8.decode(
                stderrBuilder.takeBytes(),
                allowMalformed: true,
              ),
              durationMs: stopwatch.elapsedMilliseconds,
            );
          })
          .timeout(
            timeout ?? const Duration(seconds: 60),
            onTimeout: () {
              sshSession?.close();
              throw TimeoutException('Command timed out');
            },
          );

      return result;
    } on TimeoutException {
      return SshExecResult(
        exitCode: null,
        stdout: '',
        stderr:
            'Command timed out after ${timeout?.inMilliseconds ?? 60000}ms.',
        durationMs: stopwatch.elapsedMilliseconds,
      );
    } finally {
      stopwatch.stop();
    }
  }

  Future<List<FileItem>> listFiles(SshSession session, String path) async {
    final sftp = await session.sftp();
    final items = await sftp.listdir(path);
    return items
        .map(
          (item) => FileItem(
            filename: item.filename,
            longname: item.longname,
            isDirectory: item.attr.isDirectory,
            size: item.attr.size ?? 0,
            mtime: item.attr.modifyTime != null
                ? DateTime.fromMillisecondsSinceEpoch(
                    item.attr.modifyTime! * 1000,
                  )
                : null,
          ),
        )
        .toList();
  }

  Future<int> getDirectorySize(SshSession session, String path) async {
    final quotedPath = _shellQuote(path);
    final command = [
      'if output=\$(du -sb $quotedPath 2>/dev/null); then',
      'printf "bytes:%s" "\${output%%[[:space:]]*}";',
      'elif output=\$(du -sk $quotedPath 2>/dev/null); then',
      'printf "kb:%s" "\${output%%[[:space:]]*}";',
      'else exit 1; fi',
    ].join(' ');
    final result = await session.runOperation(
      () => session.client.runWithResult('sh -lc ${_shellQuote(command)}'),
    );
    final stdout = utf8.decode(result.stdout).trim();
    final stderr = utf8.decode(result.stderr).trim();

    if (result.exitCode != null && result.exitCode != 0) {
      throw Exception(stderr.isNotEmpty ? stderr : 'Directory size failed.');
    }

    if (stdout.startsWith('bytes:')) {
      final size = int.tryParse(stdout.substring('bytes:'.length));
      if (size != null) {
        return size;
      }
    }

    if (stdout.startsWith('kb:')) {
      final size = int.tryParse(stdout.substring('kb:'.length));
      if (size != null) {
        return size * 1024;
      }
    }

    throw Exception('Invalid directory size output: $stdout');
  }

  Future<Stream<Uint8List>> readFileStream(
    SshSession session,
    String path,
  ) async {
    final sftp = await session.sftp();
    final file = await sftp.open(path);
    final controller = StreamController<Uint8List>();
    StreamSubscription? subscription;

    controller.onListen = () {
      subscription = file.read().listen(
        (data) {
          controller.add(data);
        },
        onError: (Object error, StackTrace stackTrace) {
          controller.addError(error, stackTrace);
          // 发生错误时关闭文件
          file.close();
          controller.close();
        },
        onDone: () {
          controller.close();
          file.close();
        },
      );
    };

    controller.onCancel = () async {
      await subscription?.cancel();
      await file.close();
    };

    return controller.stream;
  }

  Future<void> writeFileStream(
    SshSession session,
    String path,
    Stream<List<int>> content,
  ) async {
    final sftp = await session.sftp();
    final file = await sftp.open(
      path,
      mode:
          SftpFileOpenMode.write |
          SftpFileOpenMode.create |
          SftpFileOpenMode.truncate,
    );
    try {
      await file.write(content.cast<Uint8List>());
    } finally {
      await file.close();
    }
  }

  Future<void> rename(
    SshSession session,
    String oldPath,
    String newPath,
  ) async {
    final sftp = await session.sftp();
    await sftp.rename(oldPath, newPath);
  }

  Future<void> mkdir(SshSession session, String path) async {
    final sftp = await session.sftp();
    await sftp.mkdir(path);
  }

  Future<void> chmod(
    SshSession session,
    String path,
    String mode, {
    bool recursive = false,
  }) async {
    if (!RegExp(r'^[0-7]{3,4}$').hasMatch(mode)) {
      throw ArgumentError('Invalid permission mode');
    }

    final recursiveFlag = recursive ? ' -R' : '';
    final command = 'chmod$recursiveFlag $mode ${_shellQuote(path)}';
    await _runCheckedShellCommand(session, command);
  }

  Future<void> copy(SshSession session, String source, String target) async {
    // 使用 cp -r 命令进行复制，这比 SFTP 读写更高效
    final cmd = 'cp -r ${_shellQuote(source)} ${_shellQuote(target)}';
    await session.runOperation(() => session.client.run(cmd));
  }

  Future<void> extract(
    SshSession session,
    String archivePath,
    String targetPath,
  ) async {
    final lowerPath = archivePath.toLowerCase();
    final safeArchivePath = _shellQuote(archivePath);
    final safeTargetPath = _shellQuote(targetPath);

    late final String extractCommand;
    if (lowerPath.endsWith('.zip')) {
      extractCommand =
          'mkdir -p $safeTargetPath && unzip -oq $safeArchivePath -d $safeTargetPath';
    } else if (lowerPath.endsWith('.tar.gz') || lowerPath.endsWith('.tgz')) {
      extractCommand =
          'mkdir -p $safeTargetPath && tar -xzf $safeArchivePath -C $safeTargetPath';
    } else if (lowerPath.endsWith('.tar.bz2') || lowerPath.endsWith('.tbz2')) {
      extractCommand =
          'mkdir -p $safeTargetPath && tar -xjf $safeArchivePath -C $safeTargetPath';
    } else if (lowerPath.endsWith('.tar.xz') || lowerPath.endsWith('.txz')) {
      extractCommand =
          'mkdir -p $safeTargetPath && tar -xJf $safeArchivePath -C $safeTargetPath';
    } else if (lowerPath.endsWith('.tar')) {
      extractCommand =
          'mkdir -p $safeTargetPath && tar -xf $safeArchivePath -C $safeTargetPath';
    } else {
      throw UnsupportedError('暂不支持该压缩格式。');
    }

    await _runCheckedShellCommand(session, extractCommand);
  }

  Future<Stream<Uint8List>> downloadBatch(
    SshSession session,
    List<String> paths,
  ) async {
    // 使用 tar -czf - ...paths 命令打包并输出到 stdout
    final quotedPaths = paths.map(_shellQuote).join(' ');
    // 注意：这里假设路径是相对于当前工作目录或绝对路径。
    // 如果是绝对路径，tar 可能会报错 "removing leading /"。
    // 最好先 cd 到父目录，然后 tar 子项。这里为简化，直接 tar 绝对路径（通常 tar 会自动处理）
    // 或者使用 -P 参数（不建议）。
    // 更稳妥的方式：cd 到公共父目录。
    // 这里简单实现：直接 tar
    final cmd = 'tar -czf - $quotedPaths';
    final permit = await session.acquireOperation();
    try {
      final sshSession = await session.client.execute(cmd);
      return _releaseOperationWhenStreamDone(
        sshSession.stdout,
        permit.release,
        onCancel: sshSession.close,
      );
    } catch (_) {
      permit.release();
      rethrow;
    }
  }

  Future<void> delete(SshSession session, String path) async {
    // SFTP rmdir 在目录非空时会失败 (code 4)
    // 使用 rm -rf 命令通过 SSH 执行进行递归删除，更可靠且支持非空目录
    // 使用单引号包裹路径以避免 Shell 扩展，并转义路径中已有的单引号
    final cmd = 'rm -rf ${_shellQuote(path)}';
    final result = await session.runOperation(() => session.client.run(cmd));
    if (result.isNotEmpty) {
      final output = utf8.decode(result);
      // rm -rf 成功时通常没有输出，如果有输出通常表示错误
      if (output.trim().isNotEmpty) {
        throw Exception(output.trim());
      }
    }
  }

  void resize(SshSession session, int width, int height) {
    final shell = session.shell;
    if (shell == null) {
      throw StateError('Shell is not initialized for session ${session.id}');
    }
    shell.resizeTerminal(width, height);
  }

  void writeToShell(SshSession session, String data) {
    final shell = session.shell;
    if (shell == null) {
      throw StateError('Shell is not initialized for session ${session.id}');
    }
    shell.write(Uint8List.fromList(utf8.encode(data)));
  }

  Stream<Uint8List> _releaseOperationWhenStreamDone(
    Stream<Uint8List> stream,
    void Function() release, {
    void Function()? onCancel,
  }) {
    final controller = StreamController<Uint8List>();
    StreamSubscription<Uint8List>? subscription;
    var released = false;

    void releaseOnce() {
      if (released) {
        return;
      }

      released = true;
      release();
    }

    controller.onListen = () {
      subscription = stream.listen(
        controller.add,
        onError: controller.addError,
        onDone: () async {
          releaseOnce();
          await controller.close();
        },
      );
    };

    controller.onCancel = () async {
      await subscription?.cancel();
      onCancel?.call();
      releaseOnce();
    };

    return controller.stream;
  }
}

extension SshRepositoryStreaming on SshRepository {
  Stream<SshExecStreamEvent> copyStream(
    SshSession session,
    String source,
    String target,
  ) => execStream(
    session,
    'cp -r ${_shellQuote(source)} ${_shellQuote(target)}',
  );

  Stream<SshExecStreamEvent> deleteStream(SshSession session, String path) =>
      execStream(session, 'rm -rf ${_shellQuote(path)}');

  Stream<SshExecStreamEvent> extractStream(
    SshSession session,
    String archivePath,
    String targetPath,
  ) {
    final archive = _shellQuote(archivePath);
    final target = _shellQuote(targetPath);
    final lowerPath = archivePath.toLowerCase();
    final command = lowerPath.endsWith('.zip')
        ? 'mkdir -p $target && unzip -oq $archive -d $target'
        : lowerPath.endsWith('.tar.gz') || lowerPath.endsWith('.tgz')
        ? 'mkdir -p $target && tar -xzf $archive -C $target'
        : lowerPath.endsWith('.tar.bz2') || lowerPath.endsWith('.tbz2')
        ? 'mkdir -p $target && tar -xjf $archive -C $target'
        : lowerPath.endsWith('.tar.xz') || lowerPath.endsWith('.txz')
        ? 'mkdir -p $target && tar -xJf $archive -C $target'
        : lowerPath.endsWith('.tar')
        ? 'mkdir -p $target && tar -xf $archive -C $target'
        : throw UnsupportedError('暂不支持该压缩格式。');
    return execStream(session, command);
  }

  Stream<SshExecStreamEvent> execStream(
    SshSession session,
    String command, {
    Duration timeout = const Duration(minutes: 10),
  }) async* {
    final permit = await session.acquireOperation();
    SSHSession? commandSession;
    StreamSubscription<String>? stdoutSubscription;
    StreamSubscription<String>? stderrSubscription;
    StreamController<SshExecStreamEvent>? outputController;

    try {
      commandSession = await session.client.execute(command);
      await commandSession.stdin.close();

      final stdoutDone = Completer<void>();
      final stderrDone = Completer<void>();
      outputController = StreamController<SshExecStreamEvent>();

      void completeStream(Completer<void> completer) {
        if (!completer.isCompleted) {
          completer.complete();
        }
      }

      void completeStreamError(
        Completer<void> completer,
        Object error,
        StackTrace stackTrace,
      ) {
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      }

      stdoutSubscription = const Utf8Decoder(allowMalformed: true)
          .bind(commandSession.stdout.cast<List<int>>())
          .listen(
            (text) => outputController?.add(
              SshExecStreamEvent.output(SshExecStreamSource.stdout, text),
            ),
            onError: (Object error, StackTrace stackTrace) =>
                completeStreamError(stdoutDone, error, stackTrace),
            onDone: () => completeStream(stdoutDone),
          );
      stderrSubscription = const Utf8Decoder(allowMalformed: true)
          .bind(commandSession.stderr.cast<List<int>>())
          .listen(
            (text) => outputController?.add(
              SshExecStreamEvent.output(SshExecStreamSource.stderr, text),
            ),
            onError: (Object error, StackTrace stackTrace) =>
                completeStreamError(stderrDone, error, stackTrace),
            onDone: () => completeStream(stderrDone),
          );
      outputController.onPause = () {
        stdoutSubscription?.pause();
        stderrSubscription?.pause();
      };
      outputController.onResume = () {
        stdoutSubscription?.resume();
        stderrSubscription?.resume();
      };

      unawaited(() async {
        try {
          await Future.wait([
            stdoutDone.future,
            stderrDone.future,
            commandSession!.done,
          ]).timeout(timeout);
          if (!outputController!.isClosed) {
            outputController.add(
              SshExecStreamEvent.completed(commandSession.exitCode),
            );
          }
        } on TimeoutException {
          commandSession?.close();
          if (!outputController!.isClosed) {
            outputController.addError(
              TimeoutException('Command timed out after ${timeout.inSeconds}s'),
            );
          }
        } catch (error, stackTrace) {
          if (!outputController!.isClosed) {
            outputController.addError(error, stackTrace);
          }
        } finally {
          if (!outputController!.isClosed) {
            await outputController.close();
          }
        }
      }());

      yield* outputController.stream;
    } finally {
      await stdoutSubscription?.cancel();
      await stderrSubscription?.cancel();
      commandSession?.close();
      if (outputController != null && !outputController.isClosed) {
        await outputController.close();
      }
      permit.release();
    }
  }
}
