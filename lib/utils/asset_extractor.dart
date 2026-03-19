import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:logging/logging.dart';

final _log = Logger('AssetExtractor');

/// Extracts web assets from the app bundle to the application support directory.
/// Returns the path to the extracted web directory.
Future<String> extractWebAssets() async {
  final appDir = await getApplicationSupportDirectory();
  final webDir = Directory(path.join(appDir.path, 'web'));

  // Ensure the target directory exists
  if (!await webDir.exists()) {
    await webDir.create(recursive: true);
  }

  try {
    // Load the asset manifest to find all files in assets/web/
    final assetManifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final webAssets = assetManifest.listAssets().where((string) => string.startsWith('assets/web/')).toList();

    if (webAssets.isEmpty) {
      _log.info('No web assets found in bundle.');
      return webDir.path;
    }

    _log.info('Found ${webAssets.length} web assets. Extracting...');

    for (final assetPath in webAssets) {
      final relativePath = assetPath.replaceFirst('assets/web/', '');
      if (relativePath.isEmpty) continue;

      final file = File(path.join(webDir.path, relativePath));
      
      // Create parent directories if needed
      if (!await file.parent.exists()) {
        await file.parent.create(recursive: true);
      }
      
      final byteData = await rootBundle.load(assetPath);
      await file.writeAsBytes(byteData.buffer.asUint8List());
    }
    
    _log.info('Web assets extracted to ${webDir.path}');
  } catch (e) {
    _log.severe('Error extracting web assets: $e');
  }

  return webDir.path;
}
