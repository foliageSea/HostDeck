import 'dart:convert';
import 'dart:typed_data';

import 'package:host_deck/server/core/ssh/ssh_repository.dart';
import 'package:host_deck/server/core/ssh/ssh_session.dart';

class DockerComposeCreateEvent {
  final String event;
  final Map<String, dynamic> data;

  const DockerComposeCreateEvent(this.event, this.data);
}

class DockerComposeService {
  final SshRepository _sshRepository;

  DockerComposeService(this._sshRepository);

  Future<bool> isComposeAvailable(SshSession session) async {
    try {
      await _resolveComposeCommand(session);
      return true;
    } catch (_) {
      return false;
    }
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

  Stream<DockerComposeCreateEvent> createComposeProjectStream(
    SshSession session,
    Map<String, dynamic> payload,
  ) async* {
    final projectName = payload['projectName']?.toString().trim() ?? '';
    final workingDir = payload['workingDir']?.toString().trim() ?? '';
    final fileName = payload['fileName']?.toString().trim().isNotEmpty == true
        ? payload['fileName'].toString().trim()
        : 'docker-compose.yml';
    final content = payload['content']?.toString() ?? '';
    final start = payload['startAfterCreate'] == true;
    if (projectName.isEmpty || workingDir.isEmpty || content.trim().isEmpty) {
      throw ArgumentError('projectName, workingDir and content are required');
    }
    if (!_safeFileName(fileName)) {
      throw ArgumentError('fileName must be a .yml or .yaml file name');
    }

    yield const DockerComposeCreateEvent('phase', {
      'phase': 'prepare',
      'message': '正在准备项目目录',
    });
    await _runShell(session, ['mkdir', '-p', workingDir]);
    final composePath =
        '${workingDir.endsWith('/') ? workingDir.substring(0, workingDir.length - 1) : workingDir}/$fileName';
    yield const DockerComposeCreateEvent('phase', {
      'phase': 'write',
      'message': '正在写入 Compose 配置',
    });
    await _sshRepository.writeFileStream(
      session,
      composePath,
      Stream.value(Uint8List.fromList(utf8.encode(content))),
    );

    var started = false;
    String? startError;
    if (start) {
      yield const DockerComposeCreateEvent('phase', {
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
            yield DockerComposeCreateEvent('stderr', {'text': event.text});
          } else {
            yield DockerComposeCreateEvent('stdout', {'text': event.text});
          }
        }
        started = exitCode == 0;
        if (!started) {
          startError = stderr.toString().trim().isEmpty
              ? 'Compose command failed with exit code ${exitCode ?? 'unknown'}.'
              : stderr.toString().trim();
          if (stderr.isEmpty) {
            yield DockerComposeCreateEvent('stderr', {'text': '$startError\n'});
          }
        }
      } catch (error) {
        startError = error.toString();
        yield DockerComposeCreateEvent('stderr', {'text': '$startError\n'});
      }
    }
    yield DockerComposeCreateEvent('done', {
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
    return _runShell(session, [...command.args, ...args], workingDir: workingDir);
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
      if (command.supportsPlainProgress) ...['--ansi', 'never', '--progress', 'plain'],
      '-p',
      projectName,
      for (final file in files) ...['-f', file],
      'up',
      '-d',
    ];
    final commandText = _buildShellCommand(args, workingDir: workingDir);
    yield* _sshRepository.execStream(
      session,
      'sh -lc ${_quote(commandText)}',
    );
  }

  Future<_ComposeCommand> _resolveComposeCommand(SshSession session) async {
    try {
      await _runShell(session, const ['docker', 'compose', 'version']);
      return const _ComposeCommand(['docker', 'compose'], true);
    } catch (_) {
      await _runShell(session, const ['docker-compose', 'version']);
      return const _ComposeCommand(['docker-compose'], false);
    }
  }

  Future<String> _runShell(
    SshSession session,
    List<String> args, {
    String? workingDir,
  }) async {
    const marker = '__HOST_DECK_COMPOSE_STATUS__';
    final command = _buildShellCommand(args, workingDir: workingDir);
    final output = await _sshRepository.exec(
      session,
      'sh -lc ${_quote('$command; code=\$?; printf "\\n$marker:%s" "\$code"; exit 0')}',
    );
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

class _ComposeCommand {
  final List<String> args;
  final bool supportsPlainProgress;

  const _ComposeCommand(this.args, this.supportsPlainProgress);
}
