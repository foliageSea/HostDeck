import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:host_deck/server/features/settings/log_export_service.dart';
import 'package:host_deck/server/features/settings/settings_controller.dart';
import 'package:host_deck/server/features/settings/tls_service.dart';
import 'package:host_deck/server/routes/settings_routes.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

void main() {
  test(
    'TLS settings routes save pending config and only download public certificates',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'hostdeck-tls-api-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final service = TlsService(dataDir: directory.path);
      await service.init();
      final controller = SettingsController(
        LogExportService(logDirectory: null),
        tlsService: service,
      );
      final router = Router();
      registerSettingsRoutes(router, controller);
      final url = Uri.parse('http://localhost/api/settings/tls');
      var response = await router.call(Request('GET', url));
      expect(
        jsonDecode(await response.readAsString())['data']['active']['enabled'],
        isFalse,
      );
      response = await router.call(
        Request(
          'PUT',
          url,
          body: jsonEncode({'enabled': true, 'source': 'selfSigned'}),
        ),
      );
      final body = await response.readAsString();
      expect(response.statusCode, 200);
      expect(jsonDecode(body)['data']['restartRequired'], isTrue);
      expect(body, isNot(contains('PRIVATE KEY')));
      response = await router.call(
        Request('GET', Uri.parse('$url/certificate')),
      );
      expect(
        response.headers['content-disposition'],
        contains('hostdeck-cert.pem'),
      );
      final certificate = await response.readAsString();
      expect(certificate, contains('BEGIN CERTIFICATE'));
      expect(certificate, isNot(contains('PRIVATE KEY')));
      response = await router.call(Request('PUT', url, body: '{invalid'));
      expect(response.statusCode, 400);
      response = await router.call(Request('PUT', url, body: 'x' * 400001));
      expect(response.statusCode, 400);
    },
  );
}
