import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:host_deck/server/core/database/database_service.dart';
import 'package:host_deck/server/features/port_forwards/port_forward_repository.dart';
import 'package:host_deck/server/features/port_forwards/port_forward_rule.dart';

void main() {
  test(
    'migrates saved TCP rules and persists HTTP rules without a public listener',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'hostdeck-forward-migration-',
      );
      final raw = sqlite3.open('${directory.path}/host_deck.db');
      raw.execute('CREATE TABLE schema_version (version INTEGER NOT NULL)');
      raw.execute('INSERT INTO schema_version VALUES (21)');
      raw.execute('''CREATE TABLE port_forwards (
      id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL,
      enabled INTEGER NOT NULL, bindHost TEXT NOT NULL, localPort INTEGER NOT NULL,
      remoteHost TEXT NOT NULL, remotePort INTEGER NOT NULL,
      createdAt INTEGER, updatedAt INTEGER
    )''');
      raw.execute(
        "INSERT INTO port_forwards VALUES (1, 'Existing', 0, '127.0.0.1', 8081, '127.0.0.1', 80, 1, 1)",
      );
      raw.close();
      final database = DatabaseService(dataDir: directory.path);
      try {
        await database.init();
        final repository = PortForwardRepository(database);
        final existing = repository.getRule(1)!;
        expect(existing.protocol, 'tcp');
        expect(existing.localPort, 8081);
        expect(existing.toJson()['accessPath'], isNull);
        final rule = repository.addRule(
          PortForwardRule.fromJson({
            'name': 'Web',
            'protocol': 'http',
            'remotePort': 3000,
          }),
        );
        expect(rule.localPort, 0);
        expect(repository.getRule(rule.id!)!.protocol, 'http');
        expect(rule.toJson()['accessPath'], '/port-forward/${rule.id}/');
        repository.updateRule(rule.id!, rule.copyWith(remotePort: 4000));
        expect(repository.getRule(rule.id!)!.remotePort, 4000);
        expect(repository.getRule(1)!.protocol, 'tcp');
      } finally {
        database.close();
        await directory.delete(recursive: true);
      }
    },
  );
}
