import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:host_deck/server/features/ai_agent/ai_agent_skill_service.dart';

void main() {
  late _FakeSkillFileSystem fileSystem;
  late AiAgentSkillService service;

  setUp(() {
    fileSystem = _FakeSkillFileSystem();
    service = AiAgentSkillService.withFileSystem(fileSystem);
  });

  test('discovers valid skills and deduplicates by source priority', () async {
    fileSystem.addSkill(
      '.config/opencode/skills',
      'deploy-safe',
      description: 'OpenCode deployment guidance',
      body: 'Use the deployment checklist.',
    );
    fileSystem.addSkill(
      '.claude/skills',
      'deploy-safe',
      description: 'Lower priority duplicate',
      body: 'This copy must not be selected.',
    );
    fileSystem.addSkill(
      '.agents/skills',
      'inspect-logs',
      description: 'Read logs\nwithout changing the host.',
      body: 'Inspect relevant logs.',
      blockDescription: true,
    );
    fileSystem.addSkill(
      '.agents/skills',
      'linked-directory',
      description: 'Rejected directory link',
      directoryType: AiAgentSkillFileType.other,
    );
    fileSystem.addSkill(
      '.agents/skills',
      'linked-file',
      description: 'Rejected file link',
      fileType: AiAgentSkillFileType.other,
    );

    final skills = await service.discover('connection-1');

    expect(skills.map((skill) => skill.id), [
      'opencode:deploy-safe',
      'agents:inspect-logs',
    ]);
    expect(skills.first.source, 'opencode');
    expect(skills.last.description, 'Read logs\nwithout changing the host.');
    expect(skills.first.toJson().keys, ['id', 'name', 'description', 'source']);
  });

  test(
    'rejects invalid frontmatter, oversized files, and mismatched names',
    () async {
      fileSystem.addRawSkill(
        '.config/opencode/skills',
        'bad-yaml',
        '---\nname: [\ndescription: broken\n---\nbody',
      );
      fileSystem.addRawSkill(
        '.config/opencode/skills',
        'wrong-name',
        '---\nname: another-name\ndescription: wrong\n---\nbody',
      );
      fileSystem.addRawSkill(
        '.config/opencode/skills',
        'too-large',
        '---\nname: too-large\ndescription: large\n---\nbody',
        reportedSize: AiAgentSkillService.maxFileBytes + 1,
      );

      expect(await service.discover('connection-1'), isEmpty);
      expect(fileSystem.readPaths, hasLength(2));
      expect(
        fileSystem.readPaths.where((path) => path.contains('too-large')),
        isEmpty,
      );
    },
  );

  test('creates exact snapshots and rejects unavailable IDs', () async {
    final content = fileSystem.addSkill(
      '.config/opencode/skills',
      'deploy-safe',
      description: 'Deployment guidance',
      body: 'Do not skip checks.',
    );

    final snapshot = await service.snapshot('connection-1', [
      'opencode:deploy-safe',
    ]);

    expect(snapshot, hasLength(1));
    expect(snapshot.single.name, 'deploy-safe');
    expect(
      snapshot.single.directory,
      '/home/tester/.config/opencode/skills/deploy-safe',
    );
    expect(snapshot.single.content, content);
    expect(
      () => snapshot.add(
        const AiAgentSkillContent(
          name: 'other',
          directory: '/home/tester/.config/opencode/skills/other',
          content: 'other',
        ),
      ),
      throwsUnsupportedError,
    );
    await expectLater(
      service.snapshot('connection-1', ['claude:deploy-safe']),
      throwsA(isA<FormatException>()),
    );
  });

  test('enforces the aggregate selected content limit', () async {
    for (var i = 0; i < 3; i++) {
      fileSystem.addSkill(
        '.config/opencode/skills',
        'large-$i',
        description: 'Large skill $i',
        body: 'x' * (44 * 1024),
      );
    }

    await expectLater(
      service.snapshot('connection-1', [
        'opencode:large-0',
        'opencode:large-1',
        'opencode:large-2',
      ]),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects skill names longer than the interoperability limit', () async {
    final name = 'a' * 65;
    fileSystem.addSkill(
      '.config/opencode/skills',
      name,
      description: 'Name is too long',
    );

    expect(await service.discover('connection-1'), isEmpty);
  });
}

class _FakeSkillFileSystem implements AiAgentSkillFileSystem {
  static const _home = '/home/tester';
  final Map<String, List<String>> _directories = {};
  final Map<String, AiAgentSkillFileStat> _stats = {};
  final Map<String, List<int>> _files = {};
  final List<String> readPaths = [];

  String addSkill(
    String relativeRoot,
    String name, {
    required String description,
    String body = '',
    bool blockDescription = false,
    AiAgentSkillFileType directoryType = AiAgentSkillFileType.directory,
    AiAgentSkillFileType fileType = AiAgentSkillFileType.regularFile,
  }) {
    final descriptionYaml = blockDescription
        ? 'description: |\n  ${description.replaceAll('\n', '\n  ')}'
        : 'description: $description';
    final content = '---\nname: $name\n$descriptionYaml\n---\n$body';
    addRawSkill(
      relativeRoot,
      name,
      content,
      directoryType: directoryType,
      fileType: fileType,
    );
    return content;
  }

  void addRawSkill(
    String relativeRoot,
    String name,
    String content, {
    AiAgentSkillFileType directoryType = AiAgentSkillFileType.directory,
    AiAgentSkillFileType fileType = AiAgentSkillFileType.regularFile,
    int? reportedSize,
  }) {
    final root = '$_home/$relativeRoot';
    final directory = '$root/$name';
    final file = '$directory/SKILL.md';
    _directories.putIfAbsent(root, () => []).add(name);
    _stats[directory] = AiAgentSkillFileStat(type: directoryType);
    final bytes = utf8.encode(content);
    _stats[file] = AiAgentSkillFileStat(
      type: fileType,
      size: reportedSize ?? bytes.length,
    );
    _files[file] = bytes;
  }

  @override
  Future<String> home(String connectionId) async => _home;

  @override
  Future<AiAgentSkillFileStat?> lstat(String connectionId, String path) async =>
      _stats[path];

  @override
  Future<List<String>?> listDirectory(String connectionId, String path) async =>
      _directories[path] == null ? null : List.of(_directories[path]!);

  @override
  Future<List<int>> read(String connectionId, String path, int maxBytes) async {
    readPaths.add(path);
    final bytes = _files[path]!;
    return bytes.length <= maxBytes
        ? List.of(bytes)
        : bytes.sublist(0, maxBytes);
  }
}
