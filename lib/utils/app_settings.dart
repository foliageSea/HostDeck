import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:logging/logging.dart';

import 'runtime_paths.dart';

class AppSettings {
  static final _log = Logger('AppSettings');
  static const String _fileName = 'app_settings.json';
  static String? _dataDirOverride;

  static void configure({String? dataDir}) {
    _dataDirOverride = dataDir;
  }

  static Future<File> get _settingsFile async {
    final dir = await RuntimePaths.resolveDataDirectory(
      overridePath: _dataDirOverride,
    );
    return File(p.join(dir.path, _fileName));
  }

  static Future<int> getPort() async {
    try {
      final file = await _settingsFile;
      _log.info('Settings file path: ${file.path}');
      if (await file.exists()) {
        final content = await file.readAsString();
        final data = jsonDecode(content);
        return data['port'] ?? 8080;
      }
    } catch (e) {
      // Ignore errors and return default
    }
    return 8080;
  }

  static Future<void> savePort(int port) async {
    try {
      final file = await _settingsFile;
      final data = {'port': port};
      await file.writeAsString(jsonEncode(data));
    } catch (e) {
      // Ignore errors
    }
  }
}
