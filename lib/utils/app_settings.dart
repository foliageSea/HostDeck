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

  static Future<Map<String, dynamic>> _readSettings() async {
    final file = await _settingsFile;
    _log.info('Settings file path: ${file.path}');
    if (!await file.exists()) {
      return <String, dynamic>{};
    }

    final content = await file.readAsString();
    final data = jsonDecode(content);
    if (data is Map<String, dynamic>) {
      return data;
    }

    if (data is Map) {
      return data.map((key, value) => MapEntry(key.toString(), value));
    }

    return <String, dynamic>{};
  }

  static Future<void> _writeSettings(Map<String, dynamic> data) async {
    final file = await _settingsFile;
    await file.writeAsString(jsonEncode(data));
  }

  static Future<int> getPort() async {
    try {
      final data = await _readSettings();
      return data['port'] ?? 8080;
    } catch (e) {
      // Ignore errors and return default
    }
    return 8080;
  }

  static Future<void> savePort(int port) async {
    try {
      final data = await _readSettings();
      data['port'] = port;
      await _writeSettings(data);
    } catch (e) {
      // Ignore errors
    }
  }

  static Future<Map<String, dynamic>> getUiSettings() async {
    try {
      final data = await _readSettings();
      final uiSettings = data['uiSettings'];
      if (uiSettings is Map<String, dynamic>) {
        return uiSettings;
      }
      if (uiSettings is Map) {
        return uiSettings.map((key, value) => MapEntry(key.toString(), value));
      }
    } catch (e) {
      _log.warning('Failed to read UI settings: $e');
    }

    return <String, dynamic>{};
  }

  static Future<void> saveUiSettings(Map<String, dynamic> uiSettings) async {
    try {
      final data = await _readSettings();
      data['uiSettings'] = uiSettings;
      await _writeSettings(data);
    } catch (e) {
      _log.warning('Failed to save UI settings: $e');
    }
  }

  static Future<Directory> resolveWallpaperDirectory() async {
    final dir = await RuntimePaths.resolveDataDirectory(
      overridePath: _dataDirOverride,
    );
    final wallpaperDir = Directory(p.join(dir.path, 'wallpapers'));
    await wallpaperDir.create(recursive: true);
    return wallpaperDir;
  }
}
