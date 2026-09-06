import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:host_deck/server/features/port_forwards/chrome_launcher.dart';
import 'package:path/path.dart' as p;

void main() {
  test('uses an explicit Chrome path and fail-closed proxy arguments', () async {
    final dataDirectory = await Directory.systemTemp.createTemp(
      'hostdeck-chrome-launcher-',
    );
    addTearDown(() => dataDirectory.delete(recursive: true));
    late String startedExecutable;
    late List<String> startedArguments;
    final launcher = ChromeLauncher(
      dataDirectory: dataDirectory,
      executablePath: '/custom/chrome',
      executableExists: (path) => path == '/custom/chrome',
      processStarter: (executable, arguments) async {
        startedExecutable = executable;
        startedArguments = arguments;
      },
    );

    final result = await launcher.launch(
      profileId: 'tunnel_1',
      proxyPort: 49152,
      url: 'https://grafana.internal/dashboard',
    );

    expect(result.success, isTrue);
    expect(startedExecutable, '/custom/chrome');
    expect(
      startedArguments,
      contains('--proxy-server=socks5://127.0.0.1:49152'),
    );
    expect(startedArguments, contains('--proxy-bypass-list=<-loopback>'));
    expect(startedArguments, isNot(contains(contains('direct://'))));
    expect(
      startedArguments,
      contains(
        '--user-data-dir=${p.join(dataDirectory.path, 'secure-browser-profiles', 'tunnel_1')}',
      ),
    );
    expect(startedArguments.last, 'https://grafana.internal/dashboard');
  });

  test('auto-detects platform Chrome candidates in order', () {
    final windowsPath = p.Context(style: p.Style.windows);
    final launcher = ChromeLauncher(
      dataDirectory: Directory.systemTemp,
      platform: 'windows',
      environment: {
        'PROGRAMFILES': r'C:\Program Files',
        'LOCALAPPDATA': r'C:\Users\tester\AppData\Local',
      },
      executableExists: (path) => path.contains('tester'),
    );

    expect(
      launcher.findExecutable(),
      windowsPath.join(
        r'C:\Users\tester\AppData\Local',
        'Google',
        'Chrome',
        'Application',
        'chrome.exe',
      ),
    );
  });

  test('rejects invalid URLs before starting Chrome', () async {
    var started = false;
    final launcher = ChromeLauncher(
      dataDirectory: Directory.systemTemp,
      executablePath: '/custom/chrome',
      executableExists: (_) => true,
      processStarter: (_, _) async => started = true,
    );

    final result = await launcher.launch(
      profileId: 'tunnel-1',
      proxyPort: 49152,
      url: 'file:///etc/passwd',
    );

    expect(result.success, isFalse);
    expect(result.reason, 'invalid-request');
    expect(started, isFalse);
  });

  test('reports missing Chrome without starting a process', () async {
    final launcher = ChromeLauncher(
      dataDirectory: Directory.systemTemp,
      executableExists: (_) => false,
    );

    final result = await launcher.launch(
      profileId: 'tunnel-1',
      proxyPort: 49152,
    );

    expect(result.success, isFalse);
    expect(result.reason, 'not-installed');
  });
}
