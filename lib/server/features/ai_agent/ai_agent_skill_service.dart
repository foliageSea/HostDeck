import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';
import 'package:yaml/yaml.dart';

import 'package:host_deck/server/core/ssh/shared_ssh_session_resolver.dart';
import 'package:host_deck/server/core/ssh/ssh_service.dart';

class AiAgentSkill {
  final String id;
  final String name;
  final String description;
  final String source;

  const AiAgentSkill({
    required this.id,
    required this.name,
    required this.description,
    required this.source,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'source': source,
  };
}

class AiAgentSkillContent {
  final String name;
  final String directory;
  final String content;

  const AiAgentSkillContent({
    required this.name,
    required this.directory,
    required this.content,
  });
}

class AiAgentSkillService {
  static const maxFileBytes = 64 * 1024;
  static const maxDiscoveredSkills = 200;
  static const maxSelectedSkills = 8;
  static const maxSelectedContentBytes = 128 * 1024;
  static final _namePattern = RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$');
  static const _sources = [
    (name: 'opencode', relativePath: '.config/opencode/skills'),
    (name: 'claude', relativePath: '.claude/skills'),
    (name: 'agents', relativePath: '.agents/skills'),
  ];

  final AiAgentSkillFileSystem _fileSystem;

  AiAgentSkillService(SshService sshService)
    : _fileSystem = SftpAiAgentSkillFileSystem(sshService);

  AiAgentSkillService.withFileSystem(this._fileSystem);

  Future<List<AiAgentSkill>> discover(String connectionId) async {
    final discovered = await _discoverWithContent(connectionId);
    return List.unmodifiable(discovered.map((item) => item.skill));
  }

  Future<List<AiAgentSkillContent>> snapshot(
    String connectionId,
    List<String> skillIds,
  ) async {
    if (skillIds.length > maxSelectedSkills) {
      throw const FormatException('At most 8 skills may be selected.');
    }
    if (skillIds.toSet().length != skillIds.length) {
      throw const FormatException('skillIds must not contain duplicates.');
    }
    if (skillIds.isEmpty) return const [];

    final discovered = await _discoverWithContent(connectionId);
    final byId = {for (final item in discovered) item.skill.id: item};
    final result = <AiAgentSkillContent>[];
    var totalBytes = 0;
    for (final id in skillIds) {
      final item = byId[id];
      if (item == null) {
        throw FormatException('Unknown or unavailable skill ID: $id');
      }
      totalBytes += utf8.encode(item.content).length;
      if (totalBytes > maxSelectedContentBytes) {
        throw const FormatException('Selected skill content exceeds 128 KiB.');
      }
      result.add(
        AiAgentSkillContent(
          name: item.skill.name,
          directory: item.directory,
          content: item.content,
        ),
      );
    }
    return List.unmodifiable(result);
  }

  Future<List<_DiscoveredSkill>> _discoverWithContent(
    String connectionId,
  ) async {
    final home = await _fileSystem.home(connectionId);
    final result = <_DiscoveredSkill>[];
    final names = <String>{};

    for (final source in _sources) {
      if (result.length >= maxDiscoveredSkills) break;
      final root = _join(home, source.relativePath);
      final entries = await _fileSystem.listDirectory(connectionId, root);
      if (entries == null) continue;
      entries.sort();

      for (final directoryName in entries) {
        if (result.length >= maxDiscoveredSkills) break;
        if (!_namePattern.hasMatch(directoryName) ||
            directoryName.length > 64 ||
            names.contains(directoryName)) {
          continue;
        }
        final directoryPath = _join(root, directoryName);
        final directoryStat = await _fileSystem.lstat(
          connectionId,
          directoryPath,
        );
        if (directoryStat?.type != AiAgentSkillFileType.directory) continue;

        final filePath = _join(directoryPath, 'SKILL.md');
        final fileStat = await _fileSystem.lstat(connectionId, filePath);
        if (fileStat?.type != AiAgentSkillFileType.regularFile ||
            fileStat!.size == null ||
            fileStat.size! > maxFileBytes) {
          continue;
        }

        final bytes = await _fileSystem.read(
          connectionId,
          filePath,
          maxFileBytes + 1,
        );
        if (bytes.length > maxFileBytes) continue;
        final verifiedStat = await _fileSystem.lstat(connectionId, filePath);
        if (verifiedStat?.type != AiAgentSkillFileType.regularFile ||
            verifiedStat!.size != bytes.length) {
          continue;
        }
        final content = _decode(bytes);
        if (content == null) continue;
        final description = _parseFrontmatter(content, directoryName);
        if (description == null) continue;

        final skill = AiAgentSkill(
          id: '${source.name}:$directoryName',
          name: directoryName,
          description: description,
          source: source.name,
        );
        result.add(_DiscoveredSkill(skill, directoryPath, content));
        names.add(directoryName);
      }
    }
    return result;
  }

  String? _decode(List<int> bytes) {
    try {
      return utf8.decode(bytes);
    } on FormatException {
      return null;
    }
  }

  String? _parseFrontmatter(String content, String directoryName) {
    final lines = const LineSplitter().convert(content);
    if (lines.isEmpty || lines.first != '---') return null;
    final end = lines.indexOf('---', 1);
    if (end < 0) return null;
    try {
      final document = loadYaml(lines.sublist(1, end).join('\n'));
      if (document is! YamlMap) return null;
      final name = document['name'];
      final description = document['description'];
      if (name is! String ||
          description is! String ||
          name != directoryName ||
          !_namePattern.hasMatch(name) ||
          description.trim().isEmpty) {
        return null;
      }
      return description.trim();
    } on YamlException {
      return null;
    }
  }

  String _join(String parent, String child) =>
      parent == '/' ? '/$child' : '$parent/$child';
}

class _DiscoveredSkill {
  final AiAgentSkill skill;
  final String directory;
  final String content;

  const _DiscoveredSkill(this.skill, this.directory, this.content);
}

enum AiAgentSkillFileType { regularFile, directory, other }

class AiAgentSkillFileStat {
  final AiAgentSkillFileType type;
  final int? size;

  const AiAgentSkillFileStat({required this.type, this.size});
}

abstract interface class AiAgentSkillFileSystem {
  Future<String> home(String connectionId);

  Future<List<String>?> listDirectory(String connectionId, String path);

  Future<AiAgentSkillFileStat?> lstat(String connectionId, String path);

  Future<List<int>> read(String connectionId, String path, int maxBytes);
}

class SftpAiAgentSkillFileSystem implements AiAgentSkillFileSystem {
  final SharedSshSessionResolver _sessionResolver;

  SftpAiAgentSkillFileSystem(SshService sshService)
    : _sessionResolver = SharedSshSessionResolver(
        sshService,
        type: SharedSshSessionType.sftp,
        purpose: SshSessionPurpose.aiAgent,
      );

  @override
  Future<String> home(String connectionId) async {
    final sftp = await _sftp(connectionId);
    return sftp.absolute('.');
  }

  @override
  Future<List<String>?> listDirectory(String connectionId, String path) async {
    try {
      final sftp = await _sftp(connectionId);
      final entries = await sftp.listdir(path);
      return entries
          .map((entry) => entry.filename)
          .where((name) => name != '.' && name != '..')
          .toList();
    } on SftpStatusError catch (error) {
      if (error.code == 2) return null;
      rethrow;
    }
  }

  @override
  Future<AiAgentSkillFileStat?> lstat(String connectionId, String path) async {
    try {
      final sftp = await _sftp(connectionId);
      final attrs = await sftp.stat(path, followLink: false);
      final type = switch (attrs.mode?.type) {
        SftpFileType.regularFile => AiAgentSkillFileType.regularFile,
        SftpFileType.directory => AiAgentSkillFileType.directory,
        _ => AiAgentSkillFileType.other,
      };
      return AiAgentSkillFileStat(type: type, size: attrs.size);
    } on SftpStatusError catch (error) {
      if (error.code == 2) return null;
      rethrow;
    }
  }

  @override
  Future<List<int>> read(String connectionId, String path, int maxBytes) async {
    final sftp = await _sftp(connectionId);
    final file = await sftp.open(path);
    try {
      return await file.readBytes(length: maxBytes);
    } finally {
      await file.close();
    }
  }

  Future<SftpClient> _sftp(String connectionId) async {
    final session = await _sessionResolver.createForConnection(connectionId);
    return session.sftp();
  }
}
