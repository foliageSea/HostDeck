import 'package:flutter_test/flutter_test.dart';
import 'package:host_deck/server/app/server_cli.dart';

void main() {
  test('secure browser launch is disabled by default', () {
    final config = parseServerArgs(const []);

    expect(config.enableSecureBrowser, isFalse);
    expect(config.chromePath, isNull);
  });

  test('parses secure browser flag and custom Chrome path', () {
    final config = parseServerArgs(const [
      '--enable-secure-browser',
      '--chrome-path',
      '/opt/google/chrome',
      '--port',
      '9090',
    ]);

    expect(config.enableSecureBrowser, isTrue);
    expect(config.chromePath, '/opt/google/chrome');
    expect(config.port, 9090);
  });
}
