import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:host_deck/server/core/database/database_service.dart';
import 'package:host_deck/server/core/ssh/ssh_service.dart';
import 'package:host_deck/server/features/ai_agent/ai_agent_repository.dart';
import 'package:host_deck/server/features/ai_agent/ai_agent_secret_store.dart';
import 'package:host_deck/server/features/ai_agent/ai_agent_settings_service.dart';

void main() {
  late Directory dataDirectory;
  late DatabaseService database;
  late AiAgentRepository repository;
  late AiAgentSettingsService settingsService;

  setUp(() async {
    dataDirectory = await Directory.systemTemp.createTemp('hostdeck-ai-agent-');
    database = DatabaseService(dataDir: dataDirectory.path);
    await database.init();
    repository = AiAgentRepository(database);
    final secretStore = AiAgentSecretStore(dataDir: dataDirectory.path);
    await secretStore.init();
    settingsService = AiAgentSettingsService(repository, secretStore);
  });

  tearDown(() async {
    database.close();
    await dataDirectory.delete(recursive: true);
  });

  test('migration v11 and target-bound conversation CRUD', () {
    expect(
      database.db
          .select('SELECT version FROM schema_version')
          .single['version'],
      11,
    );

    repository.createConversation('conversation-1', 'server:7');
    repository.addMessage(
      id: 'message-1',
      conversationId: 'conversation-1',
      role: 'user',
      content: 'check status',
    );

    expect(repository.listConversations('server:7'), hasLength(1));
    expect(
      repository.listConversations('server:7').single.title,
      'check status',
    );
    expect(repository.getConversation('conversation-1', 'server:8'), isNull);
    expect(
      repository.listMessages('conversation-1').single.content,
      'check status',
    );
    expect(
      repository.deleteConversation('conversation-1', 'server:8'),
      isFalse,
    );
    expect(repository.deleteConversation('conversation-1', 'server:7'), isTrue);
    expect(repository.listMessages('conversation-1'), isEmpty);
  });

  test(
    'settings mask, preserve, replace, and explicitly clear the API key',
    () {
      final saved = settingsService.update(
        baseUrl: 'https://models.example.test/v1/',
        model: 'ops-model',
        apiKey: 'first-secret',
      );
      expect(saved.toJson(), {
        'baseUrl': 'https://models.example.test/v1',
        'model': 'ops-model',
        'hasApiKey': true,
      });
      expect(saved.toJson().containsKey('apiKey'), isFalse);
      expect(repository.getSettings().encryptedApiKey, startsWith('v1.'));
      expect(
        repository.getSettings().encryptedApiKey,
        isNot(contains('first-secret')),
      );
      expect(
        () => settingsService.update(
          baseUrl: 'https://other-models.example.test/v1',
        ),
        throwsFormatException,
      );
      expect(
        () => settingsService.resolve(
          baseUrl: 'https://other-models.example.test/v1',
        ),
        throwsFormatException,
      );
      expect(
        settingsService
            .resolve(
              baseUrl: 'https://other-models.example.test/v1',
              apiKey: 'temporary-secret',
            )
            .apiKey,
        'temporary-secret',
      );

      settingsService.update(model: 'new-model', apiKey: '');
      expect(settingsService.resolve().apiKey, 'first-secret');

      settingsService.update(apiKey: 'second-secret');
      expect(settingsService.resolve().apiKey, 'second-secret');

      final cleared = settingsService.update(clearApiKey: true);
      expect(cleared.hasApiKey, isFalse);
      expect(() => settingsService.resolve(), throwsStateError);
    },
  );

  test('validates base URL and derives stable target identities', () {
    expect(
      () => settingsService.update(baseUrl: 'file:///tmp/model'),
      throwsFormatException,
    );
    expect(
      settingsService.update(baseUrl: 'http://models.example.test/v1').baseUrl,
      'http://models.example.test/v1',
    );
    expect(
      () => settingsService.update(baseUrl: 'https://secret@example.test/v1'),
      throwsFormatException,
    );
    expect(
      const SshConnectionMetadata(
        host: 'example.test',
        port: 22,
        username: 'root',
        serverId: 42,
      ).targetKey,
      'server:42',
    );
    expect(
      const SshConnectionMetadata(
        host: 'example.test',
        port: 2222,
        username: 'deploy',
      ).targetKey,
      'deploy@example.test:2222',
    );
  });
}
