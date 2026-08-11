import 'dart:io';

import 'package:host_deck/utils/runtime_paths.dart';
import 'package:path/path.dart' as p;

const _compiledAppVersion = String.fromEnvironment(
  'HOSTDECK_VERSION',
  defaultValue: 'dev',
);

Future<Directory> resolveServerLogDirectory({
  required String? logDir,
  required String? dataDir,
}) async {
  if (logDir != null) {
    return Directory(logDir);
  }

  final dataDirectory = await RuntimePaths.resolveDataDirectory(
    overridePath: dataDir,
  );
  return Directory(p.join(dataDirectory.path, 'logs'));
}

Future<String> resolveAppVersion() async {
  final runtimeVersion = Platform.environment['HOSTDECK_VERSION'];
  if (runtimeVersion != null && runtimeVersion.isNotEmpty) {
    return runtimeVersion;
  }

  if (_compiledAppVersion != 'dev') {
    final executableDir = File(Platform.resolvedExecutable).parent;
    final versionFile = File(p.join(executableDir.parent.path, 'VERSION'));
    if (await versionFile.exists()) {
      final bundledVersion = (await versionFile.readAsString()).trim();
      if (bundledVersion.isNotEmpty) {
        return bundledVersion;
      }
    }
    return _compiledAppVersion;
  }

  final pubspec = File(p.join(Directory.current.path, 'pubspec.yaml'));
  if (!await pubspec.exists()) {
    return _compiledAppVersion;
  }

  final content = await pubspec.readAsString();
  final match = RegExp(
    r'^version:\s*([^\s#]+)',
    multiLine: true,
  ).firstMatch(content);
  return match?.group(1) ?? _compiledAppVersion;
}
