import 'dart:async';
import 'dart:convert';

import 'package:host_deck/server/core/ssh/ssh_repository.dart';
import 'package:host_deck/server/core/ssh/ssh_session.dart';

class AgentService {
  final SshRepository _repository;

  AgentService(this._repository);

  Future<Map<String, dynamic>> exec(
    SshSession session, {
    required String command,
    String? cwd,
    int? timeoutMs,
    String? stdin,
    int? maxOutputBytes,
  }) async {
    final result = await _repository.execWithResult(
      session,
      command,
      cwd: cwd,
      timeout: Duration(milliseconds: timeoutMs ?? 60000),
      stdin: stdin,
    );

    final maxBytes = maxOutputBytes ?? 512 * 1024;
    final stdout = _limitText(result.stdout, maxBytes);
    final stderr = _limitText(result.stderr, maxBytes);

    return {
      ...result.toJson(),
      'stdout': stdout.value,
      'stderr': stderr.value,
      'truncated': stdout.truncated || stderr.truncated,
    };
  }

  Future<String> readTextFile(SshSession session, String path) async {
    final stream = await _repository.readFileStream(session, path);
    final bytes = <int>[];
    await for (final chunk in stream) {
      bytes.addAll(chunk);
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  Future<void> writeTextFile(SshSession session, String path, String content) {
    return _repository.writeFileStream(
      session,
      path,
      Stream.value(utf8.encode(content)),
    );
  }

  Future<Map<String, dynamic>> applyPatch(
    SshSession session, {
    required String patch,
    String? cwd,
    int? timeoutMs,
  }) async {
    final check = await exec(
      session,
      command: 'git apply --check -',
      cwd: cwd,
      stdin: patch,
      timeoutMs: timeoutMs,
    );

    if (check['exitCode'] != 0) {
      return {'checked': false, 'applied': false, 'check': check};
    }

    final apply = await exec(
      session,
      command: 'git apply -',
      cwd: cwd,
      stdin: patch,
      timeoutMs: timeoutMs,
    );

    return {
      'checked': true,
      'applied': apply['exitCode'] == 0,
      'check': check,
      'apply': apply,
    };
  }

  _LimitedText _limitText(String value, int maxBytes) {
    final bytes = utf8.encode(value);
    if (bytes.length <= maxBytes) {
      return _LimitedText(value, false);
    }

    return _LimitedText(
      utf8.decode(bytes.take(maxBytes).toList(), allowMalformed: true),
      true,
    );
  }
}

class _LimitedText {
  final String value;
  final bool truncated;

  const _LimitedText(this.value, this.truncated);
}
