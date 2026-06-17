import 'package:flutter_test/flutter_test.dart';
import 'package:host_deck/server/models/server_config.dart';

void main() {
  group('ServerConfig', () {
    test('默认 JSON 不包含密码和私钥', () {
      final server = ServerConfig(
        id: 1,
        name: 'Test Server',
        host: '127.0.0.1',
        port: 22,
        username: 'root',
        password: 'secret',
        privateKey: 'private-key',
        createdAt: 123,
      );

      final json = server.toJson();

      expect(json, isNot(contains('password')));
      expect(json, isNot(contains('privateKey')));
      expect(json['hasPassword'], isTrue);
      expect(json['hasPrivateKey'], isTrue);
    });

    test('显式请求时 JSON 包含密码和私钥', () {
      final server = ServerConfig(
        id: 1,
        name: 'Test Server',
        host: '127.0.0.1',
        port: 22,
        username: 'root',
        password: 'secret',
        privateKey: 'private-key',
      );

      final json = server.toJson(includeSecrets: true);

      expect(json['password'], equals('secret'));
      expect(json['privateKey'], equals('private-key'));
    });
  });
}
