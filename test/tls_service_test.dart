import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:host_deck/server/features/settings/tls_service.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:host_deck/agent/hostdeck_agent_client.dart';
import 'package:basic_utils/basic_utils.dart';

void main() {
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('hostdeck-tls-test-');
  });
  tearDown(() async => directory.delete(recursive: true));

  test(
    'TLS stays disabled until restart and certificate works for IP and DNS',
    () async {
      final service = TlsService(dataDir: directory.path);
      await service.init();
      expect(service.enabled, isFalse);
      final state = await service.save({
        'enabled': true,
        'source': 'selfSigned',
        'hosts': ['192.168.1.10'],
      });
      expect(service.enabled, isFalse);
      expect(state['restartRequired'], isTrue);
      expect(state.toString(), isNot(contains('PRIVATE KEY')));
      final restarted = TlsService(dataDir: directory.path);
      await restarted.init();
      expect(restarted.enabled, isTrue);
      expect(restarted.state()['restartRequired'], isFalse);
      final cert = restarted.activeCertificate!;
      final trusted = SecurityContext()
        ..setTrustedCertificatesBytes(cert.codeUnits);
      final echo = webSocketHandler(
        (socket, _) => socket.stream.listen(socket.sink.add),
      );
      final server = await shelf_io.serve(
        (request) => request.url.path == 'ws'
            ? echo(request)
            : Response.ok(
                '{"code":200,"data":"tls"}',
                headers: {'content-type': 'application/json'},
              ),
        InternetAddress.loopbackIPv4,
        0,
        securityContext: restarted.securityContext,
      );
      final client = HttpClient(context: trusted);
      addTearDown(() async {
        client.close(force: true);
        await server.close(force: true);
      });
      for (final host in ['127.0.0.1', 'localhost']) {
        final request = await client.getUrl(
          Uri.parse('https://$host:${server.port}'),
        );
        final response = await request.close();
        expect(response.statusCode, 200);
        await response.drain<void>();
      }
      final socket = await WebSocket.connect(
        'wss://127.0.0.1:${server.port}/ws',
        customClient: client,
      );
      socket.add('encrypted');
      expect(await socket.first, 'encrypted');
      await socket.close();
      final certFile = File('${directory.path}/trusted.pem');
      await certFile.writeAsString(cert);
      final agent = HostDeckAgentClient(trustedCertificatePath: certFile.path);
      expect(
        (await agent.get('https://127.0.0.1:${server.port}', '/'))['code'],
        200,
      );
      final unchanged = await restarted.save({
        'enabled': true,
        'source': 'selfSigned',
        'hosts': ['192.168.1.10'],
      });
      expect(unchanged['restartRequired'], isFalse);
      final activeBefore = restarted.activeCertificate;
      final replacement = await restarted.save({
        'enabled': true,
        'source': 'selfSigned',
        'hosts': ['192.168.1.10'],
        'regenerate': true,
      });
      expect(replacement['restartRequired'], isTrue);
      expect(restarted.activeCertificate, activeBefore);
      expect(await restarted.savedCertificate(), isNot(activeBefore));
      final disabled = await restarted.save({
        'enabled': false,
        'source': 'selfSigned',
      });
      expect(restarted.enabled, isTrue);
      expect(disabled['restartRequired'], isTrue);
    },
  );

  test(
    'imports valid PEM and rejects mismatched keys without replacing it',
    () async {
      final first = TlsService.generateCertificate([
        'localhost',
        '127.0.0.1',
        '::1',
      ]);
      final second = TlsService.generateCertificate(['localhost']);
      final service = TlsService(dataDir: directory.path);
      await service.init();
      await service.save({
        'enabled': true,
        'source': 'imported',
        'certificatePem': first.$1,
        'privateKeyPem': first.$2,
      });
      final previous = await service.savedCertificate();
      await expectLater(
        service.save({
          'enabled': true,
          'source': 'imported',
          'certificatePem': first.$1,
          'privateKeyPem': second.$2,
        }),
        throwsA(isA<TlsValidationException>()),
      );
      expect(await service.savedCertificate(), previous);
      final restarted = TlsService(dataDir: directory.path);
      await restarted.init();
      expect(restarted.enabled, isTrue);
      expect(restarted.activeCertificate, first.$1);
    },
  );

  test('expired certificates are rejected', () async {
    final pair = CryptoUtils.generateRSAKeyPair();
    final privateKey = pair.privateKey as RSAPrivateKey;
    final csr = X509Utils.generateRsaCsrPem(
      {'CN': 'expired'},
      privateKey,
      pair.publicKey as RSAPublicKey,
    );
    final cert = X509Utils.generateSelfSignedCertificate(
      privateKey,
      csr,
      1,
      notBefore: DateTime.now().subtract(const Duration(days: 3)),
    );
    await expectLater(
      TlsService.validatePair(
        cert,
        CryptoUtils.encodeRSAPrivateKeyToPem(privateKey),
      ),
      throwsA(isA<TlsValidationException>()),
    );
  });

  test(
    'invalid import preserves saved config and running certificate',
    () async {
      final service = TlsService(dataDir: directory.path);
      await service.init();
      await service.save({'enabled': true, 'source': 'selfSigned'});
      final previous = await File('${directory.path}/tls.json').readAsString();
      await expectLater(
        service.save({
          'enabled': true,
          'source': 'imported',
          'certificatePem': await service.savedCertificate(),
          'privateKeyPem': 'invalid',
        }),
        throwsA(isA<TlsValidationException>()),
      );
      expect(await File('${directory.path}/tls.json').readAsString(), previous);
    },
  );

  test('explicit false recovers from damaged config', () async {
    await File('${directory.path}/tls.json').writeAsString('broken');
    final service = TlsService(dataDir: directory.path, enabledOverride: false);
    await service.init();
    expect(service.enabled, isFalse);
    await service.save({'enabled': false, 'source': 'selfSigned'});
    await TlsService(dataDir: directory.path).init();
  });

  test('host validation rejects URLs and preserves loopback names', () {
    expect(
      TlsService.normalizeHosts(['example.com']),
      containsAll(['localhost', '127.0.0.1', '::1', 'example.com']),
    );
    expect(
      () => TlsService.normalizeHosts(['https://example.com']),
      throwsA(isA<TlsValidationException>()),
    );
  });
}
