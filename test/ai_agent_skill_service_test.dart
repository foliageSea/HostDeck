import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:host_deck/server/core/database/database_service.dart';
import 'package:host_deck/server/features/ai_agent/ai_agent_skill_repository.dart';
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
    expect(skills.first.toJson().keys, [
      'id',
      'name',
      'description',
      'source',
      'editable',
    ]);
    expect(skills.first.editable, isFalse);
  });

  test('hides remote skills when remote visibility is disabled', () async {
    fileSystem.addSkill(
      '.config/opencode/skills',
      'remote-only',
      description: 'Remote skill',
    );

    final skills = await service.discover(
      'connection-1',
      showRemoteSkills: false,
    );

    expect(skills, isEmpty);
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

  test('validates database skill frontmatter and UTF-8 size', () {
    expect(
      AiAgentSkillService.parseContent(
        '---\nname: deploy-safe\ndescription: Deploy\n---\nbody',
      ),
      (name: 'deploy-safe', description: 'Deploy'),
    );
    for (final content in [
      'missing frontmatter',
      '---\nname: Bad Name\ndescription: Deploy\n---\n',
      '---\nname: a\ndescription: \n---\n',
      '---\nname: ${'a' * 65}\ndescription: Deploy\n---\n',
      '---\nname: a\ndescription: Deploy\n---\n${'x' * (64 * 1024)}',
    ]) {
      expect(
        () => AiAgentSkillService.parseContent(content),
        throwsFormatException,
      );
    }
  });

  test(
    'database CRUD, priority, deletion recovery, and ordered snapshots',
    () async {
      final dir = await Directory.systemTemp.createTemp('hostdeck-skills-');
      final database = DatabaseService(dataDir: dir.path);
      await database.init();
      try {
        expect(
          database.db
              .select('SELECT version FROM schema_version')
              .single['version'],
          17,
        );
        final repository = AiAgentSkillRepository(database);
        final dbContent = fileSystem.addSkill(
          '.config/opencode/skills',
          'deploy-safe',
          description: 'Remote guidance',
          body: 'Remote body',
        );
        final stored = repository.create(
          name: 'deploy-safe',
          description: 'Database guidance',
          content: dbContent.replaceAll('Remote guidance', 'Database guidance'),
        );
        expect(repository.list().single.id, stored.id);
        expect(stored.toJson()['id'], 'hostdeck:${stored.id}');
        expect(stored.toJson()['editable'], isTrue);
        expect(stored.toJson(), isNot(contains('content')));
        expect(stored.toJson(includeContent: true)['content'], stored.content);
        expect(
          repository.get(stored.id)?.content,
          contains('Database guidance'),
        );
        expect(
          () => repository.create(
            name: 'deploy-safe',
            description: 'Duplicate',
            content: dbContent,
          ),
          throwsA(
            isA<SqliteException>().having(
              (e) => e.resultCode,
              'resultCode',
              19,
            ),
          ),
        );
        fileSystem.addSkill(
          '.claude/skills',
          'second-skill',
          description: 'Second skill',
          body: 'Second body',
        );
        service = AiAgentSkillService.withFileSystem(fileSystem, repository);
        final discovered = await service.discover('connection-1');
        expect(discovered.map((skill) => skill.id), [
          'hostdeck:${stored.id}',
          'claude:second-skill',
        ]);
        expect(discovered.first.editable, isTrue);
        expect(discovered.first.source, 'hostdeck');
        final snapshot = await service.snapshot('connection-1', [
          'claude:second-skill',
          'hostdeck:${stored.id}',
        ]);
        expect(snapshot.map((item) => item.name), [
          'second-skill',
          'deploy-safe',
        ]);
        expect(snapshot.first.directory, isNotNull);
        expect(snapshot.last.directory, isNull);
        expect(snapshot.last.content, contains('Database guidance'));
        fileSystem.failHome = true;
        expect(
          (await service.discover('connection-1')).map((skill) => skill.id),
          ['hostdeck:${stored.id}'],
        );
        final databaseOnlySnapshot = await service.snapshot('connection-1', [
          'hostdeck:${stored.id}',
        ]);
        expect(databaseOnlySnapshot.single.name, 'deploy-safe');
        fileSystem.failHome = false;
        expect(
          repository
              .update(
                stored.id,
                name: 'renamed-skill',
                description: 'Updated',
                content:
                    '---\nname: renamed-skill\ndescription: Updated\n---\nnew',
              )
              ?.name,
          'renamed-skill',
        );
        expect(repository.delete(stored.id), isTrue);
        expect(repository.delete(stored.id), isFalse);
        expect(repository.get(stored.id), isNull);
        expect(
          (await service.discover('connection-1')).map((skill) => skill.id),
          ['opencode:deploy-safe', 'claude:second-skill'],
        );
        await expectLater(
          service.snapshot('connection-1', ['hostdeck:${stored.id}']),
          throwsFormatException,
        );
      } finally {
        database.close();
        await dir.delete(recursive: true);
      }
    },
  );

  test('upgrades v15 database without changing existing records', () async {
    final dir = await Directory.systemTemp.createTemp('hostdeck-skills-v15-');
    final raw = sqlite3.open('${dir.path}/host_deck.db');
    raw.execute('CREATE TABLE schema_version (version INTEGER NOT NULL)');
    raw.execute('INSERT INTO schema_version (version) VALUES (15)');
    raw.execute('CREATE TABLE existing_data (value TEXT)');
    raw.execute("INSERT INTO existing_data (value) VALUES ('retained')");
    raw.close();
    final database = DatabaseService(dataDir: dir.path);
    try {
      await database.init();
      expect(
        database.db
            .select('SELECT version FROM schema_version')
            .single['version'],
        17,
      );
      expect(
        database.db.select('SELECT value FROM existing_data').single['value'],
        'retained',
      );
      expect(
        database.db
            .select('PRAGMA table_info(ai_agent_skills)')
            .map((row) => row['name']),
        ['id', 'name', 'description', 'content', 'createdAt', 'updatedAt'],
      );
    } finally {
      database.close();
      await dir.delete(recursive: true);
    }
  });

  test('limits merged discovery to 200 with database priority', () async {
    final dir = await Directory.systemTemp.createTemp('hostdeck-skills-limit-');
    final database = DatabaseService(dataDir: dir.path);
    await database.init();
    try {
      final repository = AiAgentSkillRepository(database);
      for (var i = 0; i < 200; i++) {
        repository.create(
          name: 'stored-$i',
          description: 'Stored skill',
          content: '---\nname: stored-$i\ndescription: Stored skill\n---\n',
        );
      }
      expect(repository.count(), 200);
      fileSystem.addSkill(
        '.config/opencode/skills',
        'remote-skill',
        description: 'Remote skill',
      );
      service = AiAgentSkillService.withFileSystem(fileSystem, repository);
      final skills = await service.discover('connection-1');
      expect(skills, hasLength(200));
      expect(skills.every((skill) => skill.source == 'hostdeck'), isTrue);
      expect(repository.delete(200), isTrue);
      expect(
        (await service.discover('connection-1')).last.id,
        'opencode:remote-skill',
      );
      await expectLater(
        service.snapshot(
          'connection-1',
          List.generate(9, (i) => 'hostdeck:${i + 1}'),
        ),
        throwsFormatException,
      );
    } finally {
      database.close();
      await dir.delete(recursive: true);
    }
  });
}

class _FakeSkillFileSystem implements AiAgentSkillFileSystem {
  static const _home = '/home/tester';
  final Map<String, List<String>> _directories = {};
  final Map<String, AiAgentSkillFileStat> _stats = {};
  final Map<String, List<int>> _files = {};
  final List<String> readPaths = [];
  bool failHome = false;

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
  Future<String> home(String connectionId) async {
    if (failHome) throw StateError('SFTP unavailable');
    return _home;
  }

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
