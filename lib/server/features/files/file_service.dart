import 'dart:async';
import 'dart:typed_data';

import 'package:host_deck/server/core/ssh/ssh_repository.dart';
import 'package:host_deck/server/core/ssh/ssh_session.dart';
import 'package:host_deck/server/features/files/file_item.dart';

class FileService {
  final SshRepository _repository;

  FileService(this._repository);

  Future<List<FileItem>> listFiles(SshSession session, String path) {
    return _repository.listFiles(session, path);
  }

  Future<int> getDirectorySize(SshSession session, String path) {
    return _repository.getDirectorySize(session, path);
  }

  Future<Stream<Uint8List>> readFileStream(SshSession session, String path) {
    return _repository.readFileStream(session, path);
  }

  Future<void> writeFileStream(
    SshSession session,
    String path,
    Stream<List<int>> content,
  ) {
    return _repository.writeFileStream(session, path, content);
  }

  Future<void> delete(SshSession session, String path) {
    return _repository.delete(session, path);
  }

  Future<void> rename(SshSession session, String oldPath, String newPath) {
    return _repository.rename(session, oldPath, newPath);
  }

  Future<void> mkdir(SshSession session, String path) {
    return _repository.mkdir(session, path);
  }

  Future<void> chmod(
    SshSession session,
    String path,
    String mode, {
    bool recursive = false,
  }) {
    return _repository.chmod(session, path, mode, recursive: recursive);
  }

  Future<void> copy(SshSession session, String source, String target) {
    return _repository.copy(session, source, target);
  }

  Future<void> extract(
    SshSession session,
    String archivePath,
    String targetPath,
  ) {
    return _repository.extract(session, archivePath, targetPath);
  }

  Future<Stream<Uint8List>> downloadBatch(
    SshSession session,
    List<String> paths,
  ) {
    return _repository.downloadBatch(session, paths);
  }
}
