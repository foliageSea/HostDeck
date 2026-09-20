import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';
import 'package:yaml/yaml.dart';

import 'package:host_deck/server/core/ssh/shared_ssh_session_resolver.dart';
import 'package:host_deck/server/features/ai_agent/ai_agent_skill_repository.dart';

class AiAgentSkill {
  final String id;
  final String name;
  final String description;
  final String source;
  final bool editable;

  const AiAgentSkill({
    required this.id,
    required this.name,
    required this.description,
    required this.source,
    this.editable = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'source': source,
    'editable': editable,
  };
}

class AiAgentSkillContent {
  final String name;
  final String? directory;
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
  final AiAgentSkillRepository? _repository;

  AiAgentSkillService(
    SharedSshSessionResolver sessionResolver,
    AiAgentSkillRepository repository,
  ) : _fileSystem = SftpAiAgentSkillFileSystem(sessionResolver),
      _repository = repository;

  AiAgentSkillService.withFileSystem(this._fileSystem, [this._repository]);

  static ({String name, String description}) parseContent(String content) {
    if (utf8.encode(content).length > maxFileBytes) {
      throw const FormatException('Skill content exceeds 64 KiB.');
    }
    final lines = const LineSplitter().convert(content);
    if (lines.isEmpty || lines.first != '---') {
      throw const FormatException('Skill frontmatter is required.');
    }
    final end = lines.indexOf('---', 1);
    if (end < 0) throw const FormatException('Skill frontmatter is invalid.');
    try {
      final document = loadYaml(lines.sublist(1, end).join('\n'));
      if (document is! YamlMap) {
        throw const FormatException('Skill frontmatter is invalid.');
      }
      final name = document['name'];
      final description = document['description'];
      if (name is! String ||
          name.length > 64 ||
          !_namePattern.hasMatch(name) ||
          description is! String ||
          description.trim().isEmpty) {
        throw const FormatException('Invalid skill name or description.');
      }
      return (name: name, description: description.trim());
    } on YamlException {
      throw const FormatException('Skill frontmatter is invalid.');
    }
  }

  Future<List<AiAgentSkill>> discover(
    String connectionId, {
    bool showRemoteSkills = true,
  }) async {
    late final List<_DiscoveredSkill> discovered;
    try {
      discovered = await _discoverWithContent(
        connectionId,
        showRemoteSkills: showRemoteSkills,
      );
    } catch (_) {
      final stored = _repository?.list() ?? const <AiAgentStoredSkill>[];
      if (stored.isEmpty) rethrow;
      return List.unmodifiable(
        stored
            .take(maxDiscoveredSkills)
            .map(
              (skill) => AiAgentSkill(
                id: 'hostdeck:${skill.id}',
                name: skill.name,
                description: skill.description,
                source: 'hostdeck',
                editable: true,
              ),
            ),
      );
    }
    return List.unmodifiable(discovered.map((item) => item.skill));
  }

  Future<List<AiAgentSkillContent>> snapshot(
    String connectionId,
    List<String> skillIds, {
    bool showRemoteSkills = true,
  }) async {
    if (skillIds.length > maxSelectedSkills) {
      throw const FormatException('At most 8 skills may be selected.');
    }
    if (skillIds.toSet().length != skillIds.length) {
      throw const FormatException('skillIds must not contain duplicates.');
    }
    if (skillIds.isEmpty) return const [];

    final storedSkills = _repository?.list() ?? const <AiAgentStoredSkill>[];
    final storedById = {
      for (final skill in storedSkills) 'hostdeck:${skill.id}': skill,
    };
    if (skillIds.every((id) => id.startsWith('hostdeck:'))) {
      return _snapshotStoredSkills(skillIds, storedById);
    }

    final discovered = await _discoverWithContent(
      connectionId,
      showRemoteSkills: showRemoteSkills,
    );
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

  List<AiAgentSkillContent> _snapshotStoredSkills(
    List<String> skillIds,
    Map<String, AiAgentStoredSkill> storedById,
  ) {
    final result = <AiAgentSkillContent>[];
    var totalBytes = 0;
    for (final id in skillIds) {
      final skill = storedById[id];
      if (skill == null) {
        throw FormatException('Unknown or unavailable skill ID: $id');
      }
      totalBytes += utf8.encode(skill.content).length;
      if (totalBytes > maxSelectedContentBytes) {
        throw const FormatException('Selected skill content exceeds 128 KiB.');
      }
      result.add(
        AiAgentSkillContent(
          name: skill.name,
          directory: null,
          content: skill.content,
        ),
      );
    }
    return List.unmodifiable(result);
  }

  Future<List<_DiscoveredSkill>> _discoverWithContent(
    String connectionId, {
    bool showRemoteSkills = true,
  }) async {
    final result = <_DiscoveredSkill>[];
    final names = <String>{};

    for (final stored
        in _repository?.list().take(maxDiscoveredSkills) ??
            const <AiAgentStoredSkill>[]) {
      result.add(
        _DiscoveredSkill(
          AiAgentSkill(
            id: 'hostdeck:${stored.id}',
            name: stored.name,
            description: stored.description,
            source: 'hostdeck',
            editable: true,
          ),
          null,
          stored.content,
        ),
      );
      names.add(stored.name);
    }
    if (result.length >= maxDiscoveredSkills) return result;
    if (!showRemoteSkills) return result;
    final home = await _fileSystem.home(connectionId);

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
    try {
      final parsed = parseContent(content);
      return parsed.name == directoryName ? parsed.description : null;
    } on FormatException {
      return null;
    }
  }

  String _join(String parent, String child) =>
      parent == '/' ? '/$child' : '$parent/$child';
}

class _DiscoveredSkill {
  final AiAgentSkill skill;
  final String? directory;
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

  SftpAiAgentSkillFileSystem(this._sessionResolver);

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
