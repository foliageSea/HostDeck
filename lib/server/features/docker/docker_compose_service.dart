import 'dart:convert';
import 'dart:typed_data';

import 'package:host_deck/server/core/ssh/shell_invocation.dart';
import 'package:host_deck/server/core/ssh/ssh_repository.dart';
import 'package:host_deck/server/core/ssh/ssh_session.dart';

class DockerComposeStreamEvent {
  final String event;
  final Map<String, dynamic> data;

  const DockerComposeStreamEvent(this.event, this.data);
}

class DockerComposeService {
  final SshRepository _sshRepository;
  final ShellInvocationResolver _shellInvocationResolver;

  DockerComposeService(
    this._sshRepository, {
    ShellInvocationResolver? shellInvocationResolver,
  }) : _shellInvocationResolver =
           shellInvocationResolver ?? ShellInvocationResolver();

  /// Compose command lines are probed per connection; `docker compose version`
  /// costs two round trips, so remember the winner until the user re-checks.
  final Map<String, _ComposeCommand> _commandCache = {};

  void invalidateCache(String connectionId) {
    _commandCache.remove(connectionId);
    _shellInvocationResolver.invalidate(connectionId);
  }

  Future<bool> isComposeAvailable(SshSession session) async {
    return (await inspectAvailability(session)).available;
  }

  Future<ComposeAvailability> inspectAvailability(SshSession session) async {
    try {
      final command = await _resolveComposeCommand(session);
      return ComposeAvailability(available: true, command: command.display);
    } catch (error) {
      return ComposeAvailability(
        available: false,
        detail: _describeFailure(error),
      );
    }
  }

  String _describeFailure(Object error) {
    final message = error
        .toString()
        .replaceFirst(RegExp(r'^Exception:\s*'), '')
        .trim();
    return message.isEmpty ? '无法执行 Docker Compose 命令' : message;
  }

  Future<List<Map<String, dynamic>>> listComposeProjects(
    SshSession session,
  ) async {
    final items = _decodeItems(
      await _runCompose(session, const ['ls', '--all', '--format', 'json']),
    );
    return items
        .map(
          (item) => <String, dynamic>{
            'name': _value(item, const ['Name', 'name']),
            'status': _value(item, const ['Status', 'status']),
            'configFiles': _value(item, const ['ConfigFiles', 'configFiles']),
            'workingDir': _value(item, const ['WorkingDir', 'workingDir']),
          },
        )
        .where((item) => item['name'].toString().isNotEmpty)
        .toList();
  }

  Stream<DockerComposeStreamEvent> createComposeProjectStream(
    SshSession session,
    Map<String, dynamic> payload,
  ) async* {
    final projectName = payload['projectName']?.toString().trim() ?? '';
    final workingDir = payload['workingDir']?.toString().trim() ?? '';
    final fileName = payload['fileName']?.toString().trim().isNotEmpty == true
        ? payload['fileName'].toString().trim()
        : 'docker-compose.yml';
    final content = payload['content']?.toString() ?? '';
    final envContent = payload['envContent']?.toString() ?? '';
    final writeEnvFile = payload['writeEnvFile'] == true;
    final start = payload['startAfterCreate'] == true;
    if (projectName.isEmpty || workingDir.isEmpty || content.trim().isEmpty) {
      throw ArgumentError('projectName, workingDir and content are required');
    }
    if (!_safeFileName(fileName)) {
      throw ArgumentError('fileName must be a .yml or .yaml file name');
    }

    yield const DockerComposeStreamEvent('phase', {
      'phase': 'prepare',
      'message': '正在准备项目目录',
    });
    await _runShell(session, ['mkdir', '-p', workingDir]);
    final composePath =
        '${workingDir.endsWith('/') ? workingDir.substring(0, workingDir.length - 1) : workingDir}/$fileName';
    yield const DockerComposeStreamEvent('phase', {
      'phase': 'write',
      'message': '正在写入 Compose 配置',
    });
    await _sshRepository.writeFileStream(
      session,
      composePath,
      Stream.value(Uint8List.fromList(utf8.encode(content))),
    );
    if (writeEnvFile) {
      final envPath =
          '${workingDir.endsWith('/') ? workingDir.substring(0, workingDir.length - 1) : workingDir}/.env';
      yield const DockerComposeStreamEvent('phase', {
        'phase': 'write-env',
        'message': '正在写入 .env',
      });
      await _sshRepository.writeFileStream(
        session,
        envPath,
        Stream.value(Uint8List.fromList(utf8.encode(envContent))),
      );
    }

    var started = false;
    String? startError;
    if (start) {
      yield const DockerComposeStreamEvent('phase', {
        'phase': 'start',
        'message': '正在启动 Compose 项目',
      });
      try {
        final stderr = StringBuffer();
        int? exitCode;
        await for (final event in _streamUpComposeProject(
          session,
          projectName: projectName,
          configFiles: [composePath],
          workingDir: workingDir,
        )) {
          if (event.completed) {
            exitCode = event.exitCode;
            continue;
          }
          if (event.text.isEmpty) {
            continue;
          }
          if (event.source == SshExecStreamSource.stderr) {
            stderr.write(event.text);
            yield DockerComposeStreamEvent('stderr', {'text': event.text});
          } else {
            yield DockerComposeStreamEvent('stdout', {'text': event.text});
          }
        }
        started = exitCode == 0;
        if (!started) {
          startError = stderr.toString().trim().isEmpty
              ? 'Compose command failed with exit code ${exitCode ?? 'unknown'}.'
              : stderr.toString().trim();
          if (stderr.isEmpty) {
            yield DockerComposeStreamEvent('stderr', {'text': '$startError\n'});
          }
        }
      } catch (error) {
        startError = error.toString();
        yield DockerComposeStreamEvent('stderr', {'text': '$startError\n'});
      }
    }
    yield DockerComposeStreamEvent('done', {
      'projectName': projectName,
      'workingDir': workingDir,
      'configFiles': [composePath],
      'started': started,
      'startError': startError,
    });
  }

  Future<List<Map<String, dynamic>>> listComposeServices(
    SshSession session, {
    required String projectName,
    required List<String> configFiles,
    String? workingDir,
  }) async {
    late final List<Map<String, dynamic>> items;
    try {
      items = _decodeItems(
        await _runProject(
          session,
          projectName: projectName,
          configFiles: configFiles,
          workingDir: workingDir,
          args: const ['ps', '--format', 'json'],
        ),
      );
    } catch (_) {
      items = _parseServiceTable(
        await _runProject(
          session,
          projectName: projectName,
          configFiles: configFiles,
          workingDir: workingDir,
          args: const ['ps'],
        ),
      );
    }
    return items
        .map(
          (item) => <String, dynamic>{
            'id': _value(item, const ['ID', 'Id', 'id']),
            'name': _value(item, const ['Name', 'name']),
            'service': _value(item, const ['Service', 'service']),
            'project': _value(item, const ['Project', 'project']),
            'image': _value(item, const ['Image', 'image']),
            'state': _value(item, const ['State', 'state']),
            'status': _value(item, const ['Status', 'status']),
            'ports': _value(item, const ['Publishers', 'Ports', 'ports']),
          },
        )
        .toList();
  }

  Future<String> upComposeProject(
    SshSession session, {
    required String projectName,
    required List<String> configFiles,
    String? workingDir,
  }) => _runProject(
    session,
    projectName: projectName,
    configFiles: configFiles,
    workingDir: workingDir,
    args: const ['up', '-d'],
  );
  Future<String> stopComposeProject(
    SshSession session, {
    required String projectName,
    required List<String> configFiles,
    String? workingDir,
  }) => _runProject(
    session,
    projectName: projectName,
    configFiles: configFiles,
    workingDir: workingDir,
    args: const ['stop'],
  );
  Future<String> restartComposeProject(
    SshSession session, {
    required String projectName,
    required List<String> configFiles,
    String? workingDir,
  }) => _runProject(
    session,
    projectName: projectName,
    configFiles: configFiles,
    workingDir: workingDir,
    args: const ['restart'],
  );
  Future<String> downComposeProject(
    SshSession session, {
    required String projectName,
    required List<String> configFiles,
    String? workingDir,
  }) => _runProject(
    session,
    projectName: projectName,
    configFiles: configFiles,
    workingDir: workingDir,
    args: const ['down'],
  );
  Stream<DockerComposeStreamEvent> streamComposeProjectAction(
    SshSession session, {
    required String action,
    required String projectName,
    required List<String> configFiles,
    String? workingDir,
  }) async* {
    const actionLabels = {
      'up': '启动',
      'stop': '停止',
      'restart': '重启',
      'down': '下线',
    };
    final actionLabel = actionLabels[action];
    if (actionLabel == null) {
      throw ArgumentError('Unsupported compose project action: $action');
    }

    final files = configFiles
        .map((file) => file.trim())
        .where((file) => file.isNotEmpty)
        .toSet()
        .toList();
    if (files.isEmpty) throw ArgumentError('configFiles is required');

    yield DockerComposeStreamEvent('phase', {
      'phase': 'execute',
      'message': '正在$actionLabel Compose 项目',
    });
    final command = await _resolveComposeCommand(session);
    final commandText = _buildShellCommand([
      ...command.args,
      if (action == 'up' && command.supportsPlainProgress) ...[
        '--ansi',
        'never',
        '--progress',
        'plain',
      ],
      '-p',
      projectName,
      for (final file in files) ...['-f', file],
      action,
      if (action == 'up') '-d',
    ], workingDir: workingDir);
    final stderr = StringBuffer();
    int? exitCode;
    await for (final event in _sshRepository.execStream(
      session,
      await _wrap(session, commandText),
    )) {
      if (event.completed) {
        exitCode = event.exitCode;
      } else if (event.text.isNotEmpty) {
        final source = event.source == SshExecStreamSource.stderr
            ? 'stderr'
            : 'stdout';
        if (source == 'stderr') stderr.write(event.text);
        yield DockerComposeStreamEvent(source, {'text': event.text});
      }
    }
    if (exitCode != 0) {
      throw Exception(
        stderr.toString().trim().isEmpty
            ? 'Compose command failed with exit code ${exitCode ?? 'unknown'}.'
            : stderr.toString().trim(),
      );
    }
    yield DockerComposeStreamEvent('done', {'success': true, 'action': action});
  }

  Future<String> _runProject(
    SshSession session, {
    required String projectName,
    required List<String> configFiles,
    required List<String> args,
    String? workingDir,
  }) {
    final files = configFiles
        .map((file) => file.trim())
        .where((file) => file.isNotEmpty)
        .toSet()
        .toList();
    if (files.isEmpty) throw ArgumentError('configFiles is required');
    return _runCompose(session, [
      '-p',
      projectName,
      for (final file in files) ...['-f', file],
      ...args,
    ], workingDir: workingDir);
  }

  Future<String> _runCompose(
    SshSession session,
    List<String> args, {
    String? workingDir,
  }) async {
    final command = await _resolveComposeCommand(session);
    return _runShell(session, [
      ...command.args,
      ...args,
    ], workingDir: workingDir);
  }

  Stream<SshExecStreamEvent> _streamUpComposeProject(
    SshSession session, {
    required String projectName,
    required List<String> configFiles,
    String? workingDir,
  }) async* {
    final files = configFiles
        .map((file) => file.trim())
        .where((file) => file.isNotEmpty)
        .toSet()
        .toList();
    if (files.isEmpty) throw ArgumentError('configFiles is required');

    final command = await _resolveComposeCommand(session);
    final args = [
      ...command.args,
      if (command.supportsPlainProgress) ...[
        '--ansi',
        'never',
        '--progress',
        'plain',
      ],
      '-p',
      projectName,
      for (final file in files) ...['-f', file],
      'up',
      '-d',
    ];
    final commandText = _buildShellCommand(args, workingDir: workingDir);
    yield* _sshRepository.execStream(
      session,
      await _wrap(session, commandText),
    );
  }

  Future<_ComposeCommand> _resolveComposeCommand(SshSession session) async {
    final cached = _commandCache[session.connectionId];
    if (cached != null) {
      return cached;
    }

    final failures = <String>[];
    for (final candidate in const [
      _ComposeCommand(['docker', 'compose'], true),
      _ComposeCommand(['docker-compose'], false),
    ]) {
      try {
        await _runShell(session, [...candidate.args, 'version']);
      } catch (error) {
        failures.add('${candidate.display}: ${_describeFailure(error)}');
        continue;
      }
      _commandCache[session.connectionId] = candidate;
      return candidate;
    }

    throw Exception(failures.join('\n'));
  }

  Future<String> _runShell(
    SshSession session,
    List<String> args, {
    String? workingDir,
  }) async {
    const marker = '__HOST_DECK_COMPOSE_STATUS__';
    final command = _buildShellCommand(args, workingDir: workingDir);
    final script = await _wrap(
      session,
      '$command; code=\$?; printf "\\n$marker:%s" "\$code"; exit 0',
    );
    final output = await _sshRepository.exec(session, script);
    final index = output.lastIndexOf('\n$marker:');
    if (index < 0) {
      throw Exception(
        output.trim().isEmpty ? 'Compose command failed' : output.trim(),
      );
    }
    final body = output.substring(0, index);
    if (int.tryParse(output.substring(index + marker.length + 2).trim()) != 0) {
      throw Exception(
        body.trim().isEmpty ? 'Compose command failed' : body.trim(),
      );
    }
    return body.trim();
  }

  /// Builds the remote command with the shell flavor this connection supports.
  Future<String> _wrap(SshSession session, String script) async =>
      (await _shellInvocationResolver.resolve(session)).wrap(script);

  String _buildShellCommand(List<String> args, {String? workingDir}) => [
    if (workingDir?.trim().isNotEmpty == true)
      'cd ${_quote(workingDir!.trim())}',
    args.map(_quote).join(' '),
  ].join(' && ');

  List<Map<String, dynamic>> _decodeItems(String output) {
    final text = output.trim();
    if (text.isEmpty) {
      return [];
    }
    try {
      final decoded = jsonDecode(text);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
      }
      if (decoded is Map) {
        return [Map<String, dynamic>.from(decoded)];
      }
    } catch (_) {}
    return text
        .split('\n')
        .map(jsonDecode)
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  List<Map<String, dynamic>> _parseServiceTable(String output) {
    return output
        .split('\n')
        .map((line) => line.trim())
        .where(
          (line) => line.isNotEmpty && !line.toLowerCase().startsWith('name'),
        )
        .map((line) {
          final parts = line.split(RegExp(r'\s{2,}'));
          return <String, dynamic>{
            'Name': parts[0],
            'Service': parts[0],
            'Image': parts.length > 1 ? parts[1] : '',
            'State': parts.length > 2 ? parts[2] : '',
            'Status': parts.length > 2 ? parts.sublist(2).join(' ') : '',
            'Ports': parts.length > 3 ? parts.sublist(3).join(', ') : '',
          };
        })
        .toList();
  }

  String _value(Map<String, dynamic> item, List<String> keys) {
    for (final key in keys) {
      if (item[key] != null) return item[key].toString();
    }
    return '';
  }

  bool _safeFileName(String value) =>
      !value.contains('/') &&
      !value.contains('\\') &&
      (value.toLowerCase().endsWith('.yml') ||
          value.toLowerCase().endsWith('.yaml'));
  String _quote(String value) => "'${value.replaceAll("'", "'\\''")}'";
}

class ComposeAvailability {
  final bool available;
  final String? command;
  final String? detail;

  const ComposeAvailability({
    required this.available,
    this.command,
    this.detail,
  });

  Map<String, dynamic> toJson() => {
    'available': available,
    if (command != null) 'command': command,
    if (detail != null) 'detail': detail,
  };
}

class _ComposeCommand {
  final List<String> args;
  final bool supportsPlainProgress;

  const _ComposeCommand(this.args, this.supportsPlainProgress);

  String get display => args.join(' ');
}
