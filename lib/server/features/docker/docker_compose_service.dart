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
      final output = await _runComposeCommand(session, ['version']);
      return output.trim().isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> listComposeProjects(
    SshSession session,
  ) async {
    late final List<Map<String, dynamic>> items;
    try {
      final output = await _runComposeCommand(session, [
        'compose',
        'ls',
        '--all',
        '--format',
        'json',
      ]);
      items = _decodeComposeJsonItems(output);
    } catch (e) {
      return <Map<String, dynamic>>[];
    }

    return items
        .map((item) {
          final name = _firstString(item, ['Name', 'name']);
          final status = _firstString(item, ['Status', 'status']);
          final configFiles = _firstString(item, [
            'ConfigFiles',
            'configFiles',
            'ConfigFilesText',
          ]);
          final workingDir = _firstString(item, [
            'WorkingDir',
            'workingDir',
            'Workdir',
          ]);

          return <String, dynamic>{
            'name': name,
            'status': status,
            'configFiles': configFiles,
            'workingDir': workingDir,
          };
        })
        .where((item) => item['name'].toString().isNotEmpty)
        .toList();
  }

  Future<Map<String, dynamic>> createComposeProject(
    SshSession session,
    Map<String, dynamic> payload,
  ) async {
    final output = StringBuffer();
    Map<String, dynamic>? result;

    await for (final event in createComposeProjectStream(session, payload)) {
      if (event.event == 'stdout' || event.event == 'stderr') {
        output.write(event.data['text']?.toString() ?? '');
      } else if (event.event == 'error') {
        throw Exception(event.data['message']?.toString() ?? '创建编排项目失败');
      } else if (event.event == 'done') {
        result = Map<String, dynamic>.from(event.data);
      }
    }

    if (result == null) {
      throw Exception('创建编排项目未返回结果');
    }

    return {...result, 'output': output.toString().trim()};
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
    final startAfterCreate = payload['startAfterCreate'] == true;

    if (projectName.isEmpty) {
      throw ArgumentError('projectName is required');
    }
    if (workingDir.isEmpty) {
      throw ArgumentError('workingDir is required');
    }
    if (content.trim().isEmpty) {
      throw ArgumentError('content is required');
    }
    if (!_isSafeComposeFileName(fileName)) {
      throw ArgumentError('fileName must be a .yml or .yaml file name');
    }

    yield const DockerComposeCreateEvent('phase', {
      'phase': 'prepare',
      'message': '正在准备项目目录',
    });
    await _runShellCommand(session, ['mkdir', '-p', workingDir]);
    final composePath = _joinPath(workingDir, fileName);

    yield const DockerComposeCreateEvent('phase', {
      'phase': 'write',
      'message': '正在写入 Compose 配置',
    });
    await _sshRepository.writeFileStream(
      session,
      composePath,
      Stream.value(Uint8List.fromList(utf8.encode(content))),
    );

    String? startError;
    var started = false;
    if (startAfterCreate) {
      yield const DockerComposeCreateEvent('phase', {
        'phase': 'start',
        'message': '正在启动 Compose 项目',
      });

      try {
        final commandArgs = <String>[
          'compose',
          '-p',
          projectName,
          '-f',
          composePath,
          'up',
          '-d',
        ];
        var primaryOutput = '';
        int? primaryExitCode;
        await for (final event in _sshRepository.execStream(
          session,
          _buildShellCommand([
            'docker',
            ...commandArgs,
          ], workingDir: workingDir),
          timeout: const Duration(hours: 1),
        )) {
          if (event.completed) {
            primaryExitCode = event.exitCode;
            continue;
          }

          primaryOutput += event.text;
          if (primaryOutput.length > 64 * 1024) {
            primaryOutput = primaryOutput.substring(
              primaryOutput.length - 64 * 1024,
            );
          }
          yield DockerComposeCreateEvent(
            event.source == SshExecStreamSource.stderr ? 'stderr' : 'stdout',
            {'text': event.text},
          );
        }

        if (primaryExitCode == 0) {
          started = true;
        } else {
          yield const DockerComposeCreateEvent('phase', {
            'phase': 'fallback',
            'message': '正在尝试兼容版 docker-compose',
          });

          int? fallbackExitCode;
          await for (final event in _sshRepository.execStream(
            session,
            _buildShellCommand([
              'docker-compose',
              ...commandArgs.skip(1),
            ], workingDir: workingDir),
            timeout: const Duration(hours: 1),
          )) {
            if (event.completed) {
              fallbackExitCode = event.exitCode;
              continue;
            }

            yield DockerComposeCreateEvent(
              event.source == SshExecStreamSource.stderr ? 'stderr' : 'stdout',
              {'text': event.text},
            );
          }

          started = fallbackExitCode == 0;
          if (!started) {
            final message = primaryOutput.trim();
            startError = message.isEmpty
                ? 'Compose command failed with exit code ${primaryExitCode ?? 'unknown'}'
                : message;
          }
        }
      } catch (error) {
        startError = error.toString();
        yield DockerComposeCreateEvent('stderr', {'text': '\n$startError\n'});
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
      final output = await _runComposeProjectCommand(
        session,
        projectName: projectName,
        configFiles: configFiles,
        workingDir: workingDir,
        args: ['ps', '--format', 'json'],
      );
      items = _decodeComposeJsonItems(output);
    } catch (_) {
      final output = await _runComposeProjectCommand(
        session,
        projectName: projectName,
        configFiles: configFiles,
        workingDir: workingDir,
        args: ['ps'],
      );
      items = _parseComposeServicesTable(output);
    }

    return items.map((item) {
      return <String, dynamic>{
        'id': _firstString(item, ['ID', 'Id', 'id']),
        'name': _firstString(item, ['Name', 'name']),
        'service': _firstString(item, ['Service', 'service']),
        'project': _firstString(item, ['Project', 'project']),
        'image': _firstString(item, ['Image', 'image']),
        'state': _firstString(item, ['State', 'state']),
        'status': _firstString(item, ['Status', 'status']),
        'ports': _firstString(item, ['Publishers', 'Ports', 'ports']),
      };
    }).toList();
  }

  Future<String> upComposeProject(
    SshSession session, {
    required String projectName,
    required List<String> configFiles,
    String? workingDir,
  }) {
    return _runComposeProjectCommand(
      session,
      projectName: projectName,
      configFiles: configFiles,
      workingDir: workingDir,
      args: ['up', '-d'],
    );
  }

  Future<String> stopComposeProject(
    SshSession session, {
    required String projectName,
    required List<String> configFiles,
    String? workingDir,
  }) {
    return _runComposeProjectCommand(
      session,
      projectName: projectName,
      configFiles: configFiles,
      workingDir: workingDir,
      args: ['stop'],
    );
  }

  Future<String> restartComposeProject(
    SshSession session, {
    required String projectName,
    required List<String> configFiles,
    String? workingDir,
  }) {
    return _runComposeProjectCommand(
      session,
      projectName: projectName,
      configFiles: configFiles,
      workingDir: workingDir,
      args: ['restart'],
    );
  }

  Future<String> downComposeProject(
    SshSession session, {
    required String projectName,
    required List<String> configFiles,
    String? workingDir,
  }) {
    return _runComposeProjectCommand(
      session,
      projectName: projectName,
      configFiles: configFiles,
      workingDir: workingDir,
      args: ['down'],
    );
  }

  Future<String> getComposeLogs(
    SshSession session, {
    required String projectName,
    required List<String> configFiles,
    String? workingDir,
    int tail = 200,
  }) {
    return _runComposeProjectCommand(
      session,
      projectName: projectName,
      configFiles: configFiles,
      workingDir: workingDir,
      args: ['logs', '--no-color', '--tail', tail.toString()],
    );
  }

  List<String> _normalizeComposeFiles(List<String> files) {
    return files
        .map((file) => file.trim())
        .where((file) => file.isNotEmpty)
        .toSet()
        .toList();
  }

  bool _isSafeComposeFileName(String fileName) {
    if (fileName.contains('/') || fileName.contains('\\')) {
      return false;
    }
    final lower = fileName.toLowerCase();
    return lower.endsWith('.yml') || lower.endsWith('.yaml');
  }

  String _joinPath(String directory, String fileName) {
    final normalizedDirectory = directory.endsWith('/')
        ? directory.substring(0, directory.length - 1)
        : directory;
    return '$normalizedDirectory/$fileName';
  }

  String _buildShellCommand(List<String> args, {String? workingDir}) {
    final dockerCommand = args.map(_shellQuote).join(' ');
    final directory = workingDir?.trim();
    final command = [
      if (directory != null && directory.isNotEmpty)
        'cd ${_shellQuote(directory)}',
      dockerCommand,
    ].join(' && ');
    return 'sh -lc ${_shellQuote(command)}';
  }

  Future<String> _runComposeProjectCommand(
    SshSession session, {
    required String projectName,
    required List<String> configFiles,
    String? workingDir,
    required List<String> args,
  }) {
    final files = _normalizeComposeFiles(configFiles);
    if (files.isEmpty) {
      throw ArgumentError('configFiles is required');
    }

    final commandArgs = <String>['compose'];
    final normalizedProjectName = projectName.trim();
    if (normalizedProjectName.isNotEmpty) {
      commandArgs.addAll(['-p', normalizedProjectName]);
    }
    for (final file in files) {
      commandArgs.addAll(['-f', file]);
    }
    commandArgs.addAll(args);

    return _runComposeCommand(session, commandArgs, workingDir: workingDir);
  }

  Future<String> _runComposeCommand(
    SshSession session,
    List<String> args, {
    String? workingDir,
  }) async {
    try {
      return await _runShellCommand(session, [
        'docker',
        ...args,
      ], workingDir: workingDir);
    } catch (error) {
      if (args.isEmpty || args.first != 'compose') {
        rethrow;
      }

      try {
        return await _runShellCommand(session, [
          'docker-compose',
          ...args.skip(1),
        ], workingDir: workingDir);
      } catch (_) {
        throw error;
      }
    }
  }

  Future<String> _runShellCommand(
    SshSession session,
    List<String> args, {
    String? workingDir,
  }) async {
    const statusMarker = '__HOST_DECK_COMPOSE_STATUS__';
    final dockerCommand = args.map(_shellQuote).join(' ');
    final directory = workingDir?.trim();
    final command = [
      if (directory != null && directory.isNotEmpty)
        'cd ${_shellQuote(directory)}',
      dockerCommand,
    ].join(' && ');
    final wrappedCommand =
        'sh -lc ${_shellQuote('$command; code=\$?; printf "\\n$statusMarker:%s" "\$code"; exit 0')}';
    final output = await _sshRepository.exec(session, wrappedCommand);
    final markerIndex = output.lastIndexOf('\n$statusMarker:');
    if (markerIndex < 0) {
      throw Exception(
        output.trim().isEmpty ? 'Compose command failed' : output.trim(),
      );
    }

    final body = output.substring(0, markerIndex);
    final statusText = output
        .substring(markerIndex + statusMarker.length + 2)
        .trim();
    final statusCode = int.tryParse(statusText);
    if (statusCode == null || statusCode != 0) {
      throw Exception(
        body.trim().isEmpty ? 'Compose command failed' : body.trim(),
      );
    }

    return body.trim();
  }

  List<Map<String, dynamic>> _parseComposeServicesTable(String output) {
    return output
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .where((line) => !line.toLowerCase().startsWith('name'))
        .map((line) {
          final parts = line.split(RegExp(r'\s{2,}'));
          if (parts.isEmpty) {
            return <String, dynamic>{};
          }

          return <String, dynamic>{
            'Name': parts[0],
            'Service': parts[0],
            'Image': parts.length > 1 ? parts[1] : '',
            'State': parts.length > 2 ? parts[2] : '',
            'Status': parts.length > 2 ? parts.sublist(2).join(' ') : '',
            'Ports': parts.length > 3 ? parts.sublist(3).join(', ') : '',
          };
        })
        .where((item) => item['Name']?.toString().isNotEmpty == true)
        .toList();
  }

  List<Map<String, dynamic>> _decodeComposeJsonItems(String output) {
    final trimmed = output.trim();
    if (trimmed.isEmpty) {
      return <Map<String, dynamic>>[];
    }

    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
      }
      if (decoded is Map) {
        return [Map<String, dynamic>.from(decoded)];
      }
    } catch (_) {
      // Some compose versions output one JSON object per line.
    }

    return trimmed
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .map((line) => jsonDecode(line))
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  String _firstString(Map<String, dynamic> item, List<String> keys) {
    for (final key in keys) {
      final value = item[key];
      if (value == null) {
        continue;
      }
      if (value is List) {
        return value.map((entry) => entry.toString()).join(', ');
      }
      return value.toString();
    }
    return '';
  }

  String _shellQuote(String value) {
    return "'${value.replaceAll("'", "'\\''")}'";
  }
}
