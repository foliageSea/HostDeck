import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

class HostDeckDiscovery {
  static const int schema = 1;
  static const String envUrlKey = 'HOSTDECK_URL';
  static const String envFileKey = 'HOSTDECK_DISCOVERY_FILE';

  static Future<File> instanceFile() async {
    final override = Platform.environment[envFileKey]?.trim();
    if (override != null && override.isNotEmpty) {
      return File(override);
    }

    final home = _resolveHomeDirectory();
    return File(p.join(home, '.config', 'host-deck', 'instance.json'));
  }

  static Future<void> writeInstance({
    required String baseUrl,
    required int port,
    required String host,
    String? dataDir,
  }) async {
    final file = await instanceFile();
    await file.parent.create(recursive: true);
    final payload = <String, dynamic>{
      'schema': schema,
      'pid': pid,
      'host': host,
      'port': port,
      'baseUrl': baseUrl,
      'startedAt': DateTime.now().toUtc().toIso8601String(),
      if (dataDir != null && dataDir.isNotEmpty) 'dataDir': dataDir,
    };
    await file.writeAsString(jsonEncode(payload));
  }

  static Future<Map<String, dynamic>?> readInstance() async {
    final file = await instanceFile();
    if (!await file.exists()) {
      return null;
    }

    final decoded = jsonDecode(await file.readAsString());
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return decoded.map((key, value) => MapEntry(key.toString(), value));
    }
    return null;
  }

  static Future<void> deleteInstance() async {
    final file = await instanceFile();
    if (await file.exists()) {
      try {
        final instance = await readInstance();
        if (instance?['pid'] != pid) {
          return;
        }
      } catch (_) {
        return;
      }
      await file.delete();
    }
  }

  static String localBaseUrl(int port) => 'http://127.0.0.1:$port';

  static String _resolveHomeDirectory() {
    return Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        Directory.current.path;
  }
}
