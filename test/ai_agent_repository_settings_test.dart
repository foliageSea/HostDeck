import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:host_deck/server/core/database/database_service.dart';
import 'package:host_deck/server/core/ssh/ssh_service.dart';
import 'package:host_deck/server/features/ai_agent/ai_agent_models.dart';
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

  test('migration v17 and target-bound conversation CRUD', () {
    expect(
      database.db
          .select('SELECT version FROM schema_version')
          .single['version'],
      17,
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
    expect(
      repository.updateConversationTitle(
        'conversation-1',
        'server:8',
        'Wrong target',
      ),
      isNull,
    );
    final renamed = repository.updateConversationTitle(
      'conversation-1',
      'server:7',
      'Production status',
    );
    expect(renamed?.title, 'Production status');
    expect(
      repository.getConversation('conversation-1', 'server:7')?.title,
      'Production status',
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

  test('persists tool-call metadata, sanitizes and truncates tool output', () {
    repository.createConversation('conversation-1', 'server:7');
    repository.addMessage(
      id: 'message-user',
      conversationId: 'conversation-1',
      role: 'user',
      content: 'inspect host',
    );
    repository.addMessage(
      id: 'message-assistant',
      conversationId: 'conversation-1',
      role: 'assistant',
      content: '',
      toolCalls: const [
        AiAgentMessageToolCall(
          id: 'call-1',
          name: 'shell_execute',
          arguments: {'command': 'docker ps'},
          summary: 'Execute a remote shell command',
        ),
      ],
    );
    repository.addMessage(
      id: 'message-tool',
      conversationId: 'conversation-1',
      role: 'tool',
      content:
          'password=hunter2\n${'x' * (AiAgentRepository.maxToolContentBytes + 512)}',
      toolCallId: 'call-1',
      toolStatus: 'failed',
    );

    final messages = repository.listMessages('conversation-1');
    expect(messages.map((message) => message.id), [
      'message-user',
      'message-assistant',
      'message-tool',
    ]);
    expect(messages[1].toolCalls.single.id, 'call-1');
    expect(messages[1].toolCalls.single.arguments, {'command': 'docker ps'});
    expect(
      messages[1].toolCalls.single.summary,
      'Execute a remote shell command',
    );
    expect(messages[2].toolCallId, 'call-1');
    expect(messages[2].toolStatus, 'failed');
    expect(messages[2].content, contains('password=[redacted]'));
    expect(messages[2].content, isNot(contains('hunter2')));
    expect(messages[2].content, endsWith('[truncated]'));
    expect(
      utf8.encode(messages[2].content).length,
      lessThanOrEqualTo(AiAgentRepository.maxToolContentBytes + 64),
    );
  });

  test('serializes restored tool context for the conversation detail API', () {
    repository.createConversation('conversation-1', 'server:7');
    repository.addMessage(
      id: 'message-user',
      conversationId: 'conversation-1',
      role: 'user',
      content: 'inspect host',
    );
    repository.addMessage(
      id: 'message-assistant',
      conversationId: 'conversation-1',
      role: 'assistant',
      content: 'Checking.',
      toolCalls: const [
        AiAgentMessageToolCall(
          id: 'call-1',
          name: 'shell_execute',
          arguments: {'command': 'uptime'},
          summary: 'Execute a remote shell command',
        ),
      ],
    );
    repository.addMessage(
      id: 'message-tool',
      conversationId: 'conversation-1',
      role: 'tool',
      content: 'executed',
      toolCallId: 'call-1',
      toolStatus: 'success',
    );
    repository.addMessage(
      id: 'message-final',
      conversationId: 'conversation-1',
      role: 'assistant',
      content: 'All good.',
    );

    final json = repository
        .listMessages('conversation-1')
        .map((message) => message.toJson())
        .toList();
    expect(json[1]['toolCalls'], [
      {
        'id': 'call-1',
        'name': 'shell_execute',
        'arguments': {'command': 'uptime'},
        'summary': 'Execute a remote shell command',
      },
    ]);
    expect(json[2]['toolCallId'], 'call-1');
    expect(json[2]['toolStatus'], 'success');
    expect(json[3].containsKey('toolCalls'), isFalse);
    expect(json[3].containsKey('toolStatus'), isFalse);
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
        'models': [
          {'id': 'gpt-4o-mini', 'name': 'gpt-4o-mini'},
          {'id': 'ops-model', 'name': 'ops-model'},
        ],
        'hasApiKey': true,
        'showRemoteSkills': false,
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
      expect(settingsService.get().models.map((model) => model.id), [
        'gpt-4o-mini',
        'new-model',
        'ops-model',
      ]);
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

  test('persists remote skill visibility and defaults to disabled', () {
    expect(settingsService.get().showRemoteSkills, isFalse);
    expect(
      settingsService.update(showRemoteSkills: true).showRemoteSkills,
      isTrue,
    );
    expect(repository.getSettings().showRemoteSkills, isTrue);
    expect(
      settingsService.update(showRemoteSkills: false).showRemoteSkills,
      isFalse,
    );
  });
}
