import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:host_deck/server/core/database/database_service.dart';
import 'package:host_deck/server/features/ai_agent/ai_agent_oauth_service.dart';
import 'package:host_deck/server/features/ai_agent/ai_agent_pi_bridge.dart';
import 'package:host_deck/server/features/ai_agent/ai_agent_repository.dart';
import 'package:host_deck/server/features/ai_agent/ai_agent_secret_store.dart';
import 'package:host_deck/server/features/ai_agent/ai_agent_settings_service.dart';

class FakeBridge extends AiAgentPiBridge {
  final result = Completer<Map<String, dynamic>>();
  Map<String, dynamic>? payload;
  void Function(Map<String, dynamic>)? notify;
  bool closed = false;

  @override
  Future<Map<String, dynamic>> request(
    Map<String, dynamic> payload, {
    void Function(String)? onTextDelta,
    void Function(Map<String, dynamic>)? onAuth,
    Duration timeout = const Duration(minutes: 2),
  }) {
    this.payload = payload;
    notify = onAuth;
    return result.future;
  }

  @override
  void close() {
    closed = true;
  }
}

void main() {
  late Directory directory;
  late DatabaseService db;
  late AiAgentRepository repository;
  late AiAgentSecretStore secrets;
  late AiAgentOAuthService service;
  late List<FakeBridge> bridges;

  Map<String, dynamic> token(String value, {bool expired = false}) => {
    'type': 'oauth',
    'access': 'access-$value',
    'refresh': 'refresh-$value',
    'expires': expired ? 1 : DateTime.now().millisecondsSinceEpoch + 3600000,
    'accountId': 'account-$value',
  };

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('hostdeck-oauth-');
    db = DatabaseService(dataDir: directory.path);
    await db.init();
    repository = AiAgentRepository(db);
    secrets = AiAgentSecretStore(dataDir: directory.path);
    await secrets.init();
    bridges = [];
    service = AiAgentOAuthService(
      repository,
      secrets,
      bridgeFactory: () {
        final bridge = FakeBridge();
        bridges.add(bridge);
        return bridge;
      },
    );
  });
  tearDown(() async {
    service.dispose();
    db.close();
    await directory.delete(recursive: true);
  });

  test(
    'device login persists encrypted credentials and exposes only public status',
    () async {
      final started = service.startLogin();
      expect(started['status'], 'starting');
      bridges.single.notify!({
        'userCode': 'ABCD-EFGH',
        'verificationUri': 'https://auth.openai.com/codex/device',
        'expiresInSeconds': 900,
      });
      expect(service.status()['status'], 'pending');
      expect(service.status()['userCode'], 'ABCD-EFGH');
      bridges.single.result.complete({'credential': token('one')});
      await Future<void>.delayed(Duration.zero);
      expect(service.status()['status'], 'success');
      expect(service.authenticated, isTrue);
      expect(repository.getCredential('openai-codex'), startsWith('v1.'));
      expect(
        repository.getCredential('openai-codex'),
        isNot(contains('access-one')),
      );
      expect(jsonEncode(service.status()), isNot(contains('refresh')));
      expect((await service.credential())['access'], 'access-one');
      final settings = AiAgentSettingsService(repository, secrets);
      settings.update(
        provider: 'openai-codex',
        api: 'openai-codex-responses',
        baseUrl: 'https://chatgpt.com/backend-api',
        model: 'gpt-5.4',
      );
      expect(settings.get().toJson()['hasCredentials'], isTrue);
      expect(settings.get().hasApiKey, isFalse);
      expect(settings.resolve().oauthCredential, isNotNull);
      expect(
        () => settings.resolve(baseUrl: 'https://example.com'),
        throwsFormatException,
      );
      settings.oauth.dispose();
    },
  );

  test('cancel and logout discard late login responses', () async {
    final first = service.startLogin();
    service.cancelLogin(first['id'] as String);
    bridges[0].result.complete({'credential': token('cancelled')});
    await Future<void>.delayed(Duration.zero);
    expect(service.authenticated, isFalse);
    expect(bridges[0].closed, isTrue);
    service.startLogin();
    service.logout();
    bridges[1].result.complete({'credential': token('logged-out')});
    await Future<void>.delayed(Duration.zero);
    expect(service.authenticated, isFalse);
  });

  test(
    'concurrent expired requests share one refresh and store rotated tokens',
    () async {
      repository.saveCredential(
        'openai-codex',
        secrets.encrypt(jsonEncode(token('old', expired: true))),
      );
      final first = service.credential();
      final second = service.credential();
      expect(bridges, hasLength(1));
      expect(bridges.single.payload!['type'], 'oauth-refresh');
      bridges.single.result.complete({'credential': token('new')});
      expect((await first)['refresh'], 'refresh-new');
      expect((await second)['access'], 'access-new');
      expect((await service.credential())['refresh'], 'refresh-new');
      expect(bridges, hasLength(1));
    },
  );

  test('logout during refresh cannot resurrect credentials', () async {
    repository.saveCredential(
      'openai-codex',
      secrets.encrypt(jsonEncode(token('old', expired: true))),
    );
    final pending = service.credential();
    final expectation = expectLater(pending, throwsStateError);
    service.logout();
    bridges.single.result.complete({'credential': token('late')});
    await expectation;
    expect(service.authenticated, isFalse);
    expect(bridges.single.closed, isTrue);
  });

  test(
    'refresh errors preserve stored credentials and never expose upstream secrets',
    () async {
      final encrypted = secrets.encrypt(
        jsonEncode(token('old', expired: true)),
      );
      repository.saveCredential('openai-codex', encrypted);
      final expectation = expectLater(
        service.credential(),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            isNot(contains('upstream-secret')),
          ),
        ),
      );
      bridges.single.result.completeError(StateError('upstream-secret'));
      await expectation;
      expect(repository.getCredential('openai-codex'), encrypted);
    },
  );
}
