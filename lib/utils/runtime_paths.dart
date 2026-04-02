import 'dart:io';

import 'package:path/path.dart' as p;

class RuntimePaths {
  static const String _appDirName = 'ssh_tool';

  static Future<Directory> resolveDataDirectory({String? overridePath}) async {
    final customPath = overridePath?.trim();
    if (customPath != null && customPath.isNotEmpty) {
      final customDir = Directory(customPath);
      await customDir.create(recursive: true);
      return customDir;
    }

    final home = _resolveHomeDirectory();
    String basePath;

    if (Platform.isWindows) {
      basePath =
          Platform.environment['APPDATA'] ??
          Platform.environment['LOCALAPPDATA'] ??
          home;
    } else if (Platform.isMacOS) {
      basePath = p.join(home, 'Library', 'Application Support');
    } else {
      basePath =
          Platform.environment['XDG_DATA_HOME'] ??
          p.join(home, '.local', 'share');
    }

    final dir = Directory(p.join(basePath, _appDirName));
    await dir.create(recursive: true);
    return dir;
  }

  static String _resolveHomeDirectory() {
    return Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        Directory.current.path;
  }
}
