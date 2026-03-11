import 'dart:typed_data';
import '../repositories/ssh_repository.dart';
import '../models/ssh_session.dart';
import '../models/file_item.dart';

class FileService {
  final SshRepository _repository;

  FileService(this._repository);

  Future<List<FileItem>> listFiles(SshSession session, String path) {
    return _repository.listFiles(session, path);
  }

  Future<Uint8List> readFile(SshSession session, String path) {
    return _repository.readFile(session, path);
  }

  Future<void> writeFile(SshSession session, String path, Uint8List content) {
    return _repository.writeFile(session, path, content);
  }

  Future<void> delete(SshSession session, String path) {
    return _repository.delete(session, path);
  }
}
