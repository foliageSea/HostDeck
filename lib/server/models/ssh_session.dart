import 'dart:async';
import 'package:dartssh2/dartssh2.dart';

class SshSession {
  final String id;
  final SSHClient client;
  final SSHSession shell;
  final StreamController<String> _outputController;

  Stream<String> get output => _outputController.stream;
  StreamController<String> get outputController => _outputController;

  SshSession({
    required this.id,
    required this.client,
    required this.shell,
    StreamController<String>? outputController,
  }) : _outputController = outputController ?? StreamController.broadcast();

  Future<void> close() async {
    shell.close();
    client.close();
    await _outputController.close();
  }
}
