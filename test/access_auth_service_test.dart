import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart';

import 'package:host_deck/server/features/access/access_auth_service.dart';
import 'package:host_deck/server/features/access/access_controller.dart';
import 'package:host_deck/server/features/access/access_middleware.dart';
import 'package:host_deck/server/features/access/access_secret_store.dart';

void main() {
  group('AccessAuthService', () {
    test('allows local access when authentication is disabled', () {
      final service = AccessAuthService();
      final request = Request('GET', Uri.parse('http://localhost/api/servers'));

      expect(service.enabled, isFalse);
      expect(service.authenticate(request)?.type, 'local');
    });

    test('creates and revokes browser sessions', () {
      final service = AccessAuthService(password: 'secret');
      final token = service.createSession('secret');
      final request = Request(
        'GET',
        Uri.parse('http://localhost/api/servers'),
        headers: {'cookie': '${AccessAuthService.cookieName}=$token'},
      );

      expect(service.authenticate(request)?.type, 'browserSession');
      service.revokeSession(token);
      expect(service.authenticate(request), isNull);
    });

    test('accepts the configured API bearer token', () {
      final service = AccessAuthService(apiToken: 'agent-token');
      final request = Request(
        'GET',
        Uri.parse('http://localhost/api/agent/sessions'),
        headers: {'authorization': 'Bearer agent-token'},
      );

      expect(service.authenticate(request)?.type, 'apiToken');
    });

    test('rejects an invalid password', () {
      final service = AccessAuthService(password: 'secret');

      expect(
        () => service.createSession('wrong'),
        throwsA(isA<AccessDeniedException>()),
      );
    });

    test('generates the RFC 6238 reference code', () {
      final secret = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ';
      final time = DateTime.fromMillisecondsSinceEpoch(59 * 1000, isUtc: true);

      expect(Totp.generate(secret: secret, time: time, digits: 8), '94287082');
    });

    test('creates a browser session from a TOTP code', () async {
      final time = DateTime.fromMillisecondsSinceEpoch(59 * 1000, isUtc: true);
      const secret = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ';
      final service = AccessAuthService(totpSecret: secret, now: () => time);
      final token = await service.createTotpSession(
        Totp.generate(secret: secret, time: time),
      );

      expect(
        service
            .authenticate(
              Request(
                'GET',
                Uri.parse('http://localhost/api/servers'),
                headers: {'cookie': '${AccessAuthService.cookieName}=$token'},
              ),
            )
            ?.type,
        'browserSession',
      );
    });

    test('persists a confirmed TOTP setup and hashes recovery codes', () async {
      final directory = await Directory.systemTemp.createTemp('hostdeck-auth-');
      addTearDown(() => directory.delete(recursive: true));
      final store = AccessSecretStore(dataDir: directory.path);
      await store.init();
      final time = DateTime.fromMillisecondsSinceEpoch(59 * 1000, isUtc: true);
      final service = AccessAuthService(secretStore: store, now: () => time);

      final setup = await service.beginTotpSetup();
      final confirmed = await service.confirmTotpSetup(
        Totp.generate(secret: setup.secret, time: time),
      );

      expect(confirmed.recoveryCodes, hasLength(8));
      expect(store.totpSecret, setup.secret);
      expect(store.recoveryCodesRemaining, 8);
      expect(
        await service.createTotpSession(
          Totp.generate(secret: setup.secret, time: time),
        ),
        isNotEmpty,
      );

      final recoverySession = await service.createTotpSession(
        confirmed.recoveryCodes.first,
      );
      expect(recoverySession, isNotEmpty);
      expect(store.recoveryCodesRemaining, 7);
      await expectLater(
        service.createTotpSession(confirmed.recoveryCodes.first),
        throwsA(isA<AccessDeniedException>()),
      );

      final restored = AccessSecretStore(dataDir: directory.path);
      await restored.init();
      expect(restored.totpSecret, setup.secret);
      expect(restored.recoveryCodesRemaining, 7);
    });

    test('rate limits repeated invalid login attempts', () async {
      final time = DateTime.fromMillisecondsSinceEpoch(59 * 1000, isUtc: true);
      final service = AccessAuthService(
        totpSecret: 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ',
        now: () => time,
      );
      final controller = AccessController(service);
      Request request() => Request(
        'POST',
        Uri.parse('http://localhost/api/access/login'),
        body: '{"code":"000000"}',
        headers: {'x-forwarded-for': '192.0.2.1'},
      );

      for (var i = 0; i < 5; i++) {
        expect((await controller.login(request())).statusCode, 401);
      }
      expect((await controller.login(request())).statusCode, 429);
    });
  });

  group('accessMiddleware', () {
    Response protectedHandler(Request request) => Response.ok('ok');

    test('keeps access state public', () async {
      final handler = accessMiddleware(AccessAuthService(password: 'secret'))(
        protectedHandler,
      );

      final response = await handler(
        Request('GET', Uri.parse('http://localhost/api/access/state')),
      );

      expect(response.statusCode, 200);
    });

    test('does not block static assets', () async {
      final handler = accessMiddleware(AccessAuthService(password: 'secret'))(
        protectedHandler,
      );

      final response = await handler(
        Request('GET', Uri.parse('http://localhost/assets/index.js')),
      );

      expect(response.statusCode, 200);
    });

    test('returns HTTP 401 for an unauthenticated protected request', () async {
      final handler = accessMiddleware(AccessAuthService(password: 'secret'))(
        protectedHandler,
      );

      final response = await handler(
        Request('GET', Uri.parse('http://localhost/api/servers')),
      );

      expect(response.statusCode, 401);
    });

    test('rejects cross-origin browser session writes', () async {
      final service = AccessAuthService(password: 'secret');
      final token = service.createSession('secret');
      final handler = accessMiddleware(service)(protectedHandler);

      final response = await handler(
        Request(
          'POST',
          Uri.parse('http://localhost/api/connect'),
          headers: {
            'cookie': '${AccessAuthService.cookieName}=$token',
            'host': 'localhost',
            'origin': 'https://example.com',
          },
        ),
      );

      expect(response.statusCode, 403);
    });
  });

  group('AccessController', () {
    test('sets a HttpOnly cookie after password login', () async {
      final controller = AccessController(
        AccessAuthService(password: 'secret'),
      );

      final response = await controller.login(
        Request(
          'POST',
          Uri.parse('http://localhost/api/access/login'),
          body: '{"password":"secret"}',
        ),
      );

      expect(response.statusCode, 200);
      expect(response.headers['set-cookie'], contains('HttpOnly'));
      expect(response.headers['set-cookie'], contains('SameSite=Strict'));
    });

    test('returns HTTP 401 for an invalid password', () async {
      final controller = AccessController(
        AccessAuthService(password: 'secret'),
      );

      final response = await controller.login(
        Request(
          'POST',
          Uri.parse('http://localhost/api/access/login'),
          body: '{"password":"wrong"}',
        ),
      );

      expect(response.statusCode, 401);
    });
  });
}
