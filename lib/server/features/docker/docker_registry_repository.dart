import 'package:host_deck/server/core/database/database_service.dart';
import 'package:host_deck/server/features/docker/docker_registry_setting.dart';

class DockerRegistryRepository {
  final DatabaseService _databaseService;

  DockerRegistryRepository(this._databaseService);

  List<DockerRegistrySetting> list(String targetKey) => _databaseService.db
      .select(
        'SELECT * FROM docker_registries WHERE targetKey = ? ORDER BY id',
        [targetKey],
      )
      .map(
        (row) => DockerRegistrySetting(
          id: row['id'] as int,
          targetKey: row['targetKey'] as String,
          address: row['address'] as String,
          name: row['name'] as String,
          namespace: row['namespace'] as String,
          authentication: (row['authentication'] as int) != 0,
          username: row['username'] as String,
        ),
      )
      .toList();

  List<DockerRegistrySetting> replaceAll(
    String targetKey,
    List<DockerRegistrySetting> settings,
  ) {
    _databaseService.db.execute('BEGIN');
    try {
      _databaseService.db.execute(
        'DELETE FROM docker_registries WHERE targetKey = ?',
        [targetKey],
      );
      for (final setting in settings) {
        _databaseService.db.execute(
          '''INSERT INTO docker_registries
            (targetKey, address, name, namespace, authentication, username)
            VALUES (?, ?, ?, ?, ?, ?)''',
          [
            targetKey,
            setting.address,
            setting.name,
            setting.namespace,
            setting.authentication ? 1 : 0,
            setting.username,
          ],
        );
      }
      _databaseService.db.execute('COMMIT');
    } catch (_) {
      _databaseService.db.execute('ROLLBACK');
      rethrow;
    }
    return list(targetKey);
  }
}
