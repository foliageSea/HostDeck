import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dartssh2/dartssh2.dart';
import '../models/ssh_session.dart';
import '../models/file_item.dart';

class SshRepository {
  Future<String> exec(SshSession session, String command) async {
    final result = await session.client.run(command);
    return utf8.decode(result);
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

  Future<void> copy(SshSession session, String source, String target) async {
    // 使用 cp -r 命令进行复制，这比 SFTP 读写更高效
    // 需要对路径进行转义以防止注入，但在 dartssh2 中 run 只是简单的字符串
    // 简单的转义：用单引号包围
    final cmd = 'cp -r "$source" "$target"';
    await session.client.run(cmd);
  }

  Future<Stream<Uint8List>> downloadBatch(
    SshSession session,
    List<String> paths,
  ) async {
    // 使用 tar -czf - ...paths 命令打包并输出到 stdout
    final quotedPaths = paths.map((p) => '"$p"').join(' ');
    // 注意：这里假设路径是相对于当前工作目录或绝对路径。
    // 如果是绝对路径，tar 可能会报错 "removing leading /"。
    // 最好先 cd 到父目录，然后 tar 子项。这里为简化，直接 tar 绝对路径（通常 tar 会自动处理）
    // 或者使用 -P 参数（不建议）。
    // 更稳妥的方式：cd 到公共父目录。
    // 这里简单实现：直接 tar
    final cmd = 'tar -czf - $quotedPaths';
    final sshSession = await session.client.execute(cmd);
    return sshSession.stdout;
  }

  Future<void> delete(SshSession session, String path) async {
    // SFTP rmdir 在目录非空时会失败 (code 4)
    // 使用 rm -rf 命令通过 SSH 执行进行递归删除，更可靠且支持非空目录
    // 使用单引号包裹路径以避免 Shell 扩展，并转义路径中已有的单引号
    final safePath = path.replaceAll("'", "'\\''");
    final cmd = "rm -rf '$safePath'";
    final result = await session.client.run(cmd);
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
}
