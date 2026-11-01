import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

typedef ChromeProcessStarter =
    Future<void> Function(String executable, List<String> arguments);

class ChromeLaunchResult {
  final bool success;
  final String? reason;
  final String? message;

  const ChromeLaunchResult.success()
    : success = true,
      reason = null,
      message = null;

  const ChromeLaunchResult.failure({
    required this.reason,
    required this.message,
  }) : success = false;

  Map<String, dynamic> toJson() => {
    'success': success,
    if (reason != null) 'reason': reason,
    if (message != null) 'message': message,
  };
}

class ChromeLauncher {
  final Directory dataDirectory;
  final String? executablePath;
  final String platform;
  final Map<String, String> environment;
  final bool Function(String path) executableExists;
  final ChromeProcessStarter processStarter;
  final Future<void> Function(String directory, int proxyPort) profilePreparer;
  final _log = Logger('ChromeLauncher');

  ChromeLauncher({
    required this.dataDirectory,
    this.executablePath,
    String? platform,
    Map<String, String>? environment,
    bool Function(String path)? executableExists,
    ChromeProcessStarter? processStarter,
    Future<void> Function(String directory, int proxyPort)? profilePreparer,
  }) : platform = platform ?? Platform.operatingSystem,
       environment = environment ?? Platform.environment,
       executableExists = executableExists ?? _fileExists,
       processStarter = processStarter ?? _startProcess,
       profilePreparer = profilePreparer ?? _prepareProfile;

  String? findExecutable() {
    final customPath = executablePath?.trim();
    if (customPath != null && customPath.isNotEmpty) {
      return executableExists(customPath) ? customPath : null;
    }
    for (final candidate in chromeCandidates(platform, environment)) {
      if (executableExists(candidate)) return candidate;
    }
    return null;
  }

  bool get isChromeDetected => findExecutable() != null;

  Future<ChromeLaunchResult> launch({
    required String profileId,
    required int proxyPort,
    String? url,
  }) async {
    if (!RegExp(r'^[a-zA-Z0-9_-]{1,80}$').hasMatch(profileId)) {
      return const ChromeLaunchResult.failure(
        reason: 'invalid-request',
        message: '无效的安全浏览器配置标识。',
      );
    }
    if (proxyPort < 1 || proxyPort > 65535) {
      return const ChromeLaunchResult.failure(
        reason: 'invalid-request',
        message: '无效的代理端口。',
      );
    }

    final targetUrl = _parseUrl(url);
    if (targetUrl == null) {
      return const ChromeLaunchResult.failure(
        reason: 'invalid-request',
        message: '仅支持不包含登录凭据的 HTTP 或 HTTPS 地址。',
      );
    }

    final executable = findExecutable();
    if (executable == null) {
      return const ChromeLaunchResult.failure(
        reason: 'not-installed',
        message: '未检测到 Google Chrome，请检查 --chrome-path 配置。',
      );
    }

    try {
      final profileDirectory = Directory(
        p.join(dataDirectory.path, 'secure-browser-profiles', profileId),
      );
      await profileDirectory.create(recursive: true);
      await profilePreparer(profileDirectory.path, proxyPort);
      await processStarter(executable, [
        '--user-data-dir=${profileDirectory.path}',
        '--proxy-server=socks5://127.0.0.1:$proxyPort',
        '--proxy-bypass-list=<-loopback>',
        '--no-first-run',
        '--no-default-browser-check',
        '--new-window',
        targetUrl,
      ]);
      _log.info('Started secure Chrome profile $profileId.');
      return const ChromeLaunchResult.success();
    } catch (error) {
      _log.warning('Failed to start secure Chrome profile $profileId: $error');
      return ChromeLaunchResult.failure(
        reason: 'launch-failed',
        message: 'Google Chrome 启动失败：$error',
      );
    }
  }

  static String? _parseUrl(String? value) {
    if (value == null) return 'about:blank';
    final normalized = value.trim();
    if (normalized.isEmpty) return null;
    final uri = Uri.tryParse(normalized);
    if (uri == null ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.userInfo.isNotEmpty) {
      return null;
    }
    return uri.toString();
  }

  static bool _fileExists(String path) => File(path).existsSync();

  static bool _usesProfile(String command, String directory) {
    return ['--user-data-dir=$directory', '--user-data-dir="$directory"'].any(
      (argument) =>
          command.endsWith(argument) || command.contains('$argument '),
    );
  }

  static Future<List<({int pid, String command})>> _chromeProcesses() async {
    if (Platform.isWindows) {
      final result = await Process.run('powershell.exe', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        'ConvertTo-Json -Compress -InputObject @(Get-CimInstance Win32_Process -Filter "Name = \'chrome.exe\'" | Select-Object ProcessId,CommandLine)',
      ]);
      if (result.exitCode != 0) throw StateError('无法检查安全浏览器进程。');
      return (jsonDecode(result.stdout as String) as List).map((entry) {
        final process = entry as Map<String, dynamic>;
        return (
          pid: process['ProcessId'] as int,
          command: process['CommandLine'] as String? ?? '',
        );
      }).toList();
    }
    final result = await Process.run('/bin/ps', ['-axww', '-o', 'pid=,args=']);
    if (result.exitCode != 0) throw StateError('无法检查安全浏览器进程。');
    return (result.stdout as String).split('\n').expand((line) {
      final match = RegExp(r'^\s*(\d+)\s+(.+)$').firstMatch(line);
      return [
        if (match != null) (pid: int.parse(match[1]!), command: match[2]!),
      ];
    }).toList();
  }

  static Future<void> _prepareProfile(String directory, int proxyPort) async {
    final stale = (await _chromeProcesses())
        .where(
          (process) =>
              _usesProfile(process.command, directory) &&
              !process.command.contains('--type=') &&
              !process.command
                  .split(RegExp(r'\s+'))
                  .contains('--proxy-server=socks5://127.0.0.1:$proxyPort'),
        )
        .toList();
    for (final process in stale) {
      if (Platform.isWindows) {
        final result = await Process.run('taskkill.exe', [
          '/PID',
          '${process.pid}',
          '/T',
        ]);
        if (result.exitCode != 0) throw StateError('请关闭此主机的安全浏览器窗口后重试。');
      } else {
        Process.killPid(process.pid, ProcessSignal.sigterm);
      }
    }
    for (var attempt = 0; stale.isNotEmpty && attempt < 100; attempt++) {
      final remaining = (await _chromeProcesses()).any(
        (process) =>
            _usesProfile(process.command, directory) &&
            !process.command.contains('--type='),
      );
      if (!remaining) return;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (stale.isNotEmpty) throw StateError('请关闭此主机的安全浏览器窗口后重试。');
  }

  static Future<void> _startProcess(
    String executable,
    List<String> arguments,
  ) async {
    await Process.start(
      executable,
      arguments,
      mode: ProcessStartMode.detached,
      runInShell: false,
    );
  }
}

List<String> chromeCandidates(
  String platform,
  Map<String, String> environment,
) {
  if (platform == 'windows') {
    final windowsPath = p.Context(style: p.Style.windows);
    return [
      if (environment['PROGRAMFILES'] case final path?)
        windowsPath.join(path, 'Google', 'Chrome', 'Application', 'chrome.exe'),
      if (environment['PROGRAMFILES(X86)'] case final path?)
        windowsPath.join(path, 'Google', 'Chrome', 'Application', 'chrome.exe'),
      if (environment['LOCALAPPDATA'] case final path?)
        windowsPath.join(path, 'Google', 'Chrome', 'Application', 'chrome.exe'),
    ];
  }
  if (platform == 'macos') {
    return [
      '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
      if (environment['HOME'] case final home?)
        p.join(
          home,
          'Applications',
          'Google Chrome.app',
          'Contents',
          'MacOS',
          'Google Chrome',
        ),
    ];
  }
  return const [
    '/usr/bin/google-chrome',
    '/usr/bin/google-chrome-stable',
    '/usr/local/bin/google-chrome',
  ];
}
