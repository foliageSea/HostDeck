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
    final sftp = await session.client.sftp();
    try {
      final items = await sftp.listdir(path);
      return items.map((item) => FileItem(
        filename: item.filename,
        longname: item.longname,
        isDirectory: item.attr.isDirectory,
        size: item.attr.size ?? 0,
        mtime: item.attr.modifyTime != null 
            ? DateTime.fromMillisecondsSinceEpoch(item.attr.modifyTime! * 1000) 
            : null,
      )).toList();
    } finally {
      sftp.close();
    }
  }

  Future<Uint8List> readFile(SshSession session, String path) async {
    final sftp = await session.client.sftp();
    try {
      final file = await sftp.open(path);
      final stat = await file.stat();
      final size = stat.size ?? 0;
      if (size == 0) return Uint8List(0);
      return await file.readBytes(length: size);
    } finally {
      sftp.close();
    }
  }

  Future<void> writeFile(SshSession session, String path, Uint8List content) async {
    final sftp = await session.client.sftp();
    try {
      final file = await sftp.open(path, mode: SftpFileOpenMode.write | SftpFileOpenMode.create | SftpFileOpenMode.truncate);
      await file.writeBytes(content);
    } finally {
      sftp.close();
    }
  }

  Future<void> delete(SshSession session, String path) async {
    final sftp = await session.client.sftp();
    try {
      final stat = await sftp.stat(path);
      if (stat.isDirectory) {
        await sftp.rmdir(path);
      } else {
        await sftp.remove(path);
      }
    } finally {
      sftp.close();
    }
  }

  void resize(SshSession session, int width, int height) {
    session.shell.resizeTerminal(width, height);
  }

  void writeToShell(SshSession session, String data) {
    session.shell.write(Uint8List.fromList(utf8.encode(data)));
  }
}
