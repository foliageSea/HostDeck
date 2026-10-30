import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:host_deck/agent/hostdeck_agent_client.dart';

void main() {
  test(
    'server applies saved TLS after restart, sets secure cookies and supports CLI discovery',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'hostdeck-tls-server-',
      );
      Process? process;
      var logs = '';
      Future<void> stop() async {
        final child = process;
        process = null;
        if (child != null) {
          child.kill();
          await child.exitCode.timeout(const Duration(seconds: 10));
        }
      }

      addTearDown(() async {
        await stop();
        await directory.delete(recursive: true);
      });
      Future<Map<String, dynamic>> start() async {
        final ready = File('${directory.path}/ready.json');
        if (await ready.exists()) await ready.delete();
        final reservation = await ServerSocket.bind(
          InternetAddress.loopbackIPv4,
          0,
        );
        final port = reservation.port;
        await reservation.close();
        process = await Process.start(
          'dart',
          [
            'run',
            'bin/server.dart',
            '--port',
            '$port',
            '--data-dir',
            directory.path,
            '--ready-file',
            ready.path,
          ],
          environment: {
            'HOSTDECK_DISCOVERY_FILE': '${directory.path}/instance.json',
            'HOSTDECK_ACCESS_PASSWORD': 'test-password',
            'HOSTDECK_API_TOKEN': 'test-token',
          },
        );
        process!.stdout
            .transform(utf8.decoder)
            .listen((value) => logs += value);
        process!.stderr
            .transform(utf8.decoder)
            .listen((value) => logs += value);
        for (var i = 0; i < 400; i++) {
          if (await ready.exists()) {
            try {
              return jsonDecode(await ready.readAsString())
                  as Map<String, dynamic>;
            } on FormatException {
              // The ready file may still be in its first write.
            }
          }
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        fail('Server failed to start: $logs');
      }

      var ready = await start();
      var client = HostDeckAgentClient(token: 'test-token');
      final initialUrl = ready['baseUrl'] as String;
      expect(initialUrl, startsWith('http://'));
      Future<Map<String, dynamic>> save(
        String url,
        bool enabled, [
        String? pem,
      ]) async {
        final context = SecurityContext();
        if (pem != null) context.setTrustedCertificatesBytes(utf8.encode(pem));
        final http = HttpClient(context: context);
        try {
          final request = await http.putUrl(Uri.parse('$url/api/settings/tls'));
          request.headers.set('authorization', 'Bearer test-token');
          request.headers.contentType = ContentType.json;
          request.write(
            jsonEncode({'enabled': enabled, 'source': 'selfSigned'}),
          );
          final response = await request.close();
          return jsonDecode(await response.transform(utf8.decoder).join())
              as Map<String, dynamic>;
        } finally {
          http.close(force: true);
        }
      }

      final saved = await save(initialUrl, true);
      expect(saved['data']['restartRequired'], isTrue);
      expect(
        (await client.get(
          initialUrl,
          '/api/settings/tls',
        ))['data']['active']['enabled'],
        isFalse,
      );
      await stop();
      ready = await start();
      final tlsUrl = ready['baseUrl'] as String;
      expect(tlsUrl, startsWith('https://'));
      final electronProbe = await Process.run('node', [
        '-e',
        '''
const fs = require('node:fs');
const { waitForUrl } = require('./host-deck-electron/src/shared/dev-server.cjs');
const { probeOptions } = require('./host-deck-electron/src/main/backend-tls.cjs');
const ready = JSON.parse(fs.readFileSync(process.argv[1], 'utf8'));
waitForUrl(ready.baseUrl, 2000, probeOptions(ready.certificatePem)).catch((error) => {
  console.error(error); process.exitCode = 1;
});
''',
        '${directory.path}/ready.json',
      ]);
      expect(electronProbe.exitCode, 0, reason: '${electronProbe.stderr}');
      final certificateFile = File('${directory.path}/trust.pem');
      await certificateFile.writeAsString(ready['certificatePem'] as String);
      client = HostDeckAgentClient(
        token: 'test-token',
        trustedCertificatePath: certificateFile.path,
      );
      expect(
        (await client.get(
          tlsUrl,
          '/api/settings/tls',
        ))['data']['active']['enabled'],
        isTrue,
      );
      final context = SecurityContext()
        ..setTrustedCertificatesBytes(
          utf8.encode(ready['certificatePem'] as String),
        );
      final http = HttpClient(context: context);
      try {
        final request = await http.postUrl(
          Uri.parse('$tlsUrl/api/access/login'),
        );
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode({'password': 'test-password'}));
        final response = await request.close();
        expect(response.statusCode, 200);
        expect(response.cookies.single.secure, isTrue);
        await response.drain<void>();
      } finally {
        http.close(force: true);
      }
      final cli = await Process.run(
        'dart',
        ['run', 'bin/hostdeck_cli.dart', 'discover'],
        environment: {
          'HOSTDECK_DISCOVERY_FILE': '${directory.path}/instance.json',
          'HOSTDECK_TOKEN': 'test-token',
        },
      );
      expect(cli.exitCode, 0, reason: '${cli.stdout}\n${cli.stderr}');
      final cliOutput = cli.stdout as String;
      expect(
        jsonDecode(
          cliOutput.substring(cliOutput.indexOf('{')),
        )['data']['baseUrl'],
        tlsUrl,
      );
      await save(tlsUrl, false, ready['certificatePem'] as String);
      await stop();
      ready = await start();
      expect(ready['baseUrl'], startsWith('http://'));
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );
}
