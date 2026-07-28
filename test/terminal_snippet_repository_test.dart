import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:host_deck/server/core/database/database_service.dart';
import 'package:host_deck/server/features/terminal/terminal_snippet.dart';
import 'package:host_deck/server/features/terminal/terminal_snippet_repository.dart';

void main() {
  group('TerminalSnippetRepository', () {
    late DatabaseService databaseService;
    late Directory dataDirectory;
    late TerminalSnippetRepository repository;

    setUp(() async {
      dataDirectory = await Directory.systemTemp.createTemp('host_deck_test_');
      databaseService = DatabaseService(dataDir: dataDirectory.path);
      await databaseService.init();
      repository = TerminalSnippetRepository(databaseService);
    });

    tearDown(() async {
      databaseService.close();
      await dataDirectory.delete(recursive: true);
    });

    test('creates, updates, lists, and deletes snippets', () {
      final created = repository.add(
        const TerminalSnippet(name: 'View logs', command: 'docker logs app'),
      );

      expect(created.id, isNotNull);
      expect(created.createdAt, isNotNull);
      expect(created.updatedAt, isNotNull);
      expect(repository.getAll(), hasLength(1));

      final updated = repository.update(
        created.id!,
        const TerminalSnippet(
          name: 'Follow logs',
          command: 'docker logs -f app',
        ),
      );
      expect(updated?.name, 'Follow logs');
      expect(updated?.command, 'docker logs -f app');

      expect(repository.delete(created.id!), isTrue);
      expect(repository.getAll(), isEmpty);
    });

    test('returns null when updating an unknown snippet', () {
      final snippet = const TerminalSnippet(
        name: 'View processes',
        command: 'ps aux',
      );

      expect(repository.update(404, snippet), isNull);
      expect(repository.delete(404), isFalse);
    });
  });
}
