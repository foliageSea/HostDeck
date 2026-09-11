import 'dart:async';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:host_deck/server/core/database/database_service.dart';
import 'package:host_deck/server/core/ssh/ssh_operation_limiter.dart';
import 'package:host_deck/server/core/ssh/ssh_repository.dart';
import 'package:host_deck/server/core/ssh/ssh_session.dart';
import 'package:host_deck/server/features/docker/docker_config_service.dart';
import 'package:host_deck/server/features/docker/docker_registry_repository.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('migrates the temporary v7 registry key without losing data', () async {
    final directory = await Directory.systemTemp.createTemp(
      'host-deck-docker-migration-',
    );
    final rawDatabase = sqlite3.open('${directory.path}/host_deck.db');
    rawDatabase.execute(
      'CREATE TABLE schema_version (version INTEGER NOT NULL)',
    );
    rawDatabase.execute('INSERT INTO schema_version (version) VALUES (7)');
    rawDatabase.execute('''
      CREATE TABLE docker_registries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        connectionId TEXT NOT NULL,
        address TEXT NOT NULL,
        name TEXT NOT NULL,
        namespace TEXT NOT NULL DEFAULT '',
        authentication INTEGER NOT NULL DEFAULT 0,
        username TEXT NOT NULL DEFAULT '',
        UNIQUE(connectionId, address)
      )
    ''');
    rawDatabase.execute(
      '''INSERT INTO docker_registries
        (connectionId, address, name, namespace, authentication, username)
        VALUES (?, ?, ?, ?, ?, ?)''',
      ['legacy-connection', 'registry.example.com', '旧仓库', 'team', 1, 'deploy'],
    );
    rawDatabase.close();

    final migrated = DatabaseService(dataDir: directory.path);
    try {
      await migrated.init();
      final columns = migrated.db
          .select('PRAGMA table_info(docker_registries)')
          .map((row) => row['name'])
          .toList();
      final row = migrated.db.select('SELECT * FROM docker_registries').single;

      expect(columns, contains('targetKey'));
      expect(columns, isNot(contains('connectionId')));
      expect(row['targetKey'], 'legacy-connection');
      expect(row['address'], 'registry.example.com');
      expect(
        migrated.db
            .select('SELECT version FROM schema_version')
            .single['version'],
        8,
      );
    } finally {
      migrated.close();
      await directory.delete(recursive: true);
    }
  });

  late DatabaseService database;
  late DockerRegistryRepository registryRepository;
  late _FakeSshRepository sshRepository;
  late DockerConfigService service;
  late _FakeSshSession session;

  setUp(() async {
    database = DatabaseService(
      dataDir: (await Directory.systemTemp.createTemp(
        'host-deck-docker-config-',
      )).path,
    );
    await database.init();
    registryRepository = DockerRegistryRepository(database);
    sshRepository = _FakeSshRepository();
    service = DockerConfigService(sshRepository, registryRepository);
    session = _FakeSshSession();
  });

  tearDown(() async {
    final path =
        database.db.select('PRAGMA database_list').first['file'] as String;
    database.close();
    await Directory(path).parent.delete(recursive: true);
  });

  test('updates mirrors without changing proxy or unrelated settings', () async {
    sshRepository.results.addAll([
      const SshExecResult(
        exitCode: 0,
        stdout:
            '{"log-driver":"local","registry-mirrors":["https://old.example"],"proxies":{"http-proxy":"http://old.proxy:7890"}}',
        stderr: '',
        durationMs: 1,
      ),
      _success,
      _success,
      const SshExecResult(
        exitCode: 0,
        stdout:
            '{"log-driver":"local","registry-mirrors":["https://new.example"],"proxies":{"http-proxy":"http://old.proxy:7890"}}',
        stderr: '',
        durationMs: 1,
      ),
      const SshExecResult(
        exitCode: 0,
        stdout: 'machine-1:deploy',
        stderr: '',
        durationMs: 1,
      ),
    ]);

    await service.updateDaemonConfig(session, {
      'mirrors': ['https://new.example'],
    });

    final written = sshRepository.stdinValues[1]!;
    expect(written, contains('"log-driver": "local"'));
    expect(written, contains('"registry-mirrors"'));
    expect(written, contains('"http-proxy": "http://old.proxy:7890"'));
    expect(sshRepository.commands[2], contains('systemctl restart docker'));
  });

  test('stores registry metadata without persisting its password', () async {
    sshRepository.results.addAll([
      const SshExecResult(
        exitCode: 0,
        stdout: 'machine-1:deploy',
        stderr: '',
        durationMs: 1,
      ),
      _success,
    ]);

    final result = await service.updateRegistries(session, [
      {
        'address': 'registry.example.com',
        'name': '生产仓库',
        'namespace': 'team',
        'authentication': true,
        'username': 'deploy',
        'password': 'secret',
      },
    ]);

    expect(sshRepository.commands.last, contains('docker login'));
    expect(sshRepository.stdinValues.last, 'secret');
    expect(result.single, isNot(contains('password')));
    expect(
      registryRepository.list('machine-1:deploy').single.username,
      'deploy',
    );
  });
}

const _success = SshExecResult(
  exitCode: 0,
  stdout: '',
  stderr: '',
  durationMs: 1,
);

class _FakeSshRepository extends SshRepository {
  final results = <SshExecResult>[];
  final commands = <String>[];
  final stdinValues = <String?>[];

  @override
  Future<SshExecResult> execWithResult(
    SshSession session,
    String command, {
    String? cwd,
    Duration? timeout,
    String? stdin,
  }) async {
    commands.add(command);
    stdinValues.add(stdin);
    return results.removeAt(0);
  }
}

class _FakeSshSession implements SshSession {
  @override
  String get id => 'session-1';
  @override
  String get connectionId => 'connection-1';
  @override
  SSHClient get client => throw UnimplementedError();
  @override
  SSHSession? get shell => null;
  @override
  final SshOperationLimiter operationLimiter = SshOperationLimiter(
    maxConcurrentOperations: 1,
  );
  @override
  Stream<String> get output => const Stream.empty();
  @override
  StreamController<String> get outputController => StreamController.broadcast();
  @override
  Future<SshOperationPermit> acquireOperation() => operationLimiter.acquire();
  @override
  Future<T> runOperation<T>(FutureOr<T> Function() action) =>
      operationLimiter.run(action);
  @override
  Future<SftpClient> sftp() => throw UnimplementedError();
  @override
  Future<void> close() async {}
}
