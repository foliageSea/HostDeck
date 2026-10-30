import 'dart:convert';
import 'dart:io';

import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf_multipart/shelf_multipart.dart';

import 'package:host_deck/server/app/server_runtime.dart';
import 'package:host_deck/server/core/http/result.dart';
import 'package:host_deck/server/features/settings/log_export_service.dart';
import 'package:host_deck/server/features/settings/backend_ports_service.dart';
import 'package:host_deck/utils/app_settings.dart';
import 'package:host_deck/server/features/settings/tls_service.dart';

class SettingsController {
  final LogExportService _logExportService;
  final BackendPortsService? _backendPortsService;
  final TlsService? _tlsService;

  SettingsController(
    this._logExportService, {
    BackendPortsService? backendPortsService,
    TlsService? tlsService,
  }) : _backendPortsService = backendPortsService,
       _tlsService = tlsService;

  Response getTlsSettings(Request request) {
    final service = _tlsService;
    if (service == null) return Result.fail(503, 'TLS 配置服务不可用。');
    return Result.ok(
      service.state(),
    ).change(headers: {'cache-control': 'no-store'});
  }

  Future<Response> saveTlsSettings(Request request) async {
    final service = _tlsService;
    if (service == null) return Result.fail(503, 'TLS 配置服务不可用。');
    try {
      final bytes = <int>[];
      await for (final chunk in request.read()) {
        if (bytes.length + chunk.length > 400000) {
          return Result.fail(400, 'TLS 配置请求过大。');
        }
        bytes.addAll(chunk);
      }
      final data = jsonDecode(utf8.decode(bytes));
      if (data is! Map<String, dynamic>) return Result.fail(400, 'TLS 配置无效。');
      return Result.ok(await service.save(data));
    } on TlsValidationException catch (error) {
      return Result.fail(400, error.message);
    } on FormatException {
      return Result.fail(400, 'TLS 配置格式无效。');
    } catch (_) {
      return Result.fail(500, '保存 TLS 配置失败。');
    }
  }

  Future<Response> downloadTlsCertificate(Request request) async {
    try {
      final pem = await _tlsService?.savedCertificate();
      if (pem == null) return Result.fail(404, '尚未配置 TLS 证书。');
      return Response.ok(
        pem,
        headers: {
          'content-type': 'application/x-pem-file',
          'content-disposition': 'attachment; filename="hostdeck-cert.pem"',
          'cache-control': 'no-store',
        },
      );
    } catch (_) {
      return Result.fail(500, '读取 TLS 证书失败。');
    }
  }

  Future<Response> getServiceVersion(Request request) async {
    try {
      return Result.ok({'version': await resolveAppVersion()});
    } catch (_) {
      return Result.fail(500, '获取后端服务版本失败。');
    }
  }

  Future<Response> getBackendPorts(Request request) async {
    try {
      final service = _backendPortsService;
      if (service == null) {
        return Result.fail(503, '后端端口服务不可用。');
      }
      return Result.ok({'items': await service.list()});
    } catch (_) {
      return Result.fail(500, '获取后端端口失败。');
    }
  }

  Future<Response> getUiSettings(Request request) async {
    try {
      final settings = await AppSettings.getUiSettings();
      return Result.ok(settings);
    } catch (e) {
      return Result.fail(500, e.toString());
    }
  }

  Future<Response> saveUiSettings(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body);
      if (data is! Map) {
        return Result.fail(400, 'Invalid settings payload');
      }

      final nextSettings = data.map(
        (key, value) => MapEntry(key.toString(), value),
      );
      final previousSettings = await AppSettings.getUiSettings();

      await _deleteReplacedWallpaper(
        previousSettings['desktopWallpaper'],
        nextSettings['desktopWallpaper'],
      );
      await _deleteReplacedWallpaper(
        previousSettings['loginWallpaper'],
        nextSettings['loginWallpaper'],
      );
      await AppSettings.saveUiSettings(nextSettings);

      return Result.ok(nextSettings);
    } catch (e) {
      return Result.fail(500, e.toString());
    }
  }

  Future<Response> uploadWallpaper(Request request) async {
    try {
      final target = request.url.queryParameters['target'];
      if (target != 'desktop' && target != 'login') {
        return Result.fail(400, 'Invalid wallpaper target');
      }

      final multipart = request.multipart();
      if (multipart == null) {
        return Result.fail(400, 'Expected multipart request');
      }

      await for (final part in multipart.parts) {
        final contentDisposition = part.headers['content-disposition'];
        if (contentDisposition == null) {
          continue;
        }

        final headerValue = HeaderValue.parse(contentDisposition);
        final filename = headerValue.parameters['filename'];
        if (filename == null || filename.trim().isEmpty) {
          continue;
        }

        final extension = _resolveExtension(
          filename,
          part.headers['content-type'],
        );
        final savedFileName =
            '${target}_${DateTime.now().millisecondsSinceEpoch}$extension';
        final wallpaperDir = await AppSettings.resolveWallpaperDirectory();
        final file = File(p.join(wallpaperDir.path, savedFileName));
        await file.create(recursive: true);
        await part.pipe(file.openWrite());

        final customType = _resolveCustomType(
          part.headers['content-type'],
          filename,
        );
        if (customType == null) {
          await file.delete();
          return Result.fail(400, 'Unsupported wallpaper file type');
        }

        return Result.ok({
          'customType': customType,
          'url': '/wallpapers/$savedFileName',
        });
      }

      return Result.fail(400, 'No wallpaper file found');
    } catch (e) {
      return Result.fail(500, e.toString());
    }
  }

  Future<Response> exportLogs(Request request) async {
    try {
      final archive = await _logExportService.createArchive();
      final now = DateTime.now();
      final timestamp =
          '${now.year.toString().padLeft(4, '0')}'
          '${now.month.toString().padLeft(2, '0')}'
          '${now.day.toString().padLeft(2, '0')}T'
          '${now.hour.toString().padLeft(2, '0')}'
          '${now.minute.toString().padLeft(2, '0')}'
          '${now.second.toString().padLeft(2, '0')}';
      return Response.ok(
        archive.openReadAndDelete(),
        headers: {
          HttpHeaders.contentTypeHeader: 'application/zip',
          'content-disposition':
              'attachment; filename="hostdeck-logs-$timestamp.zip"',
          HttpHeaders.cacheControlHeader: 'no-store',
          'x-content-type-options': 'nosniff',
        },
      );
    } on LogExportUnavailable catch (error) {
      return Result.fail(404, error.message);
    } catch (_) {
      return Result.fail(500, '导出日志失败。');
    }
  }

  Future<void> _deleteReplacedWallpaper(dynamic previous, dynamic next) async {
    final previousUrl = _extractCustomUrl(previous);
    final nextUrl = _extractCustomUrl(next);
    if (previousUrl == null || previousUrl == nextUrl) {
      return;
    }

    final file = await _resolveWallpaperFile(previousUrl);
    if (file != null && await file.exists()) {
      await file.delete();
    }
  }

  String? _extractCustomUrl(dynamic settings) {
    if (settings is! Map) {
      return null;
    }

    final mode = settings['mode']?.toString();
    final customDataUrl = settings['customDataUrl']?.toString();
    if (mode != 'custom' ||
        customDataUrl == null ||
        !customDataUrl.startsWith('/wallpapers/')) {
      return null;
    }

    return customDataUrl;
  }

  Future<File?> _resolveWallpaperFile(String url) async {
    const prefix = '/wallpapers/';
    if (!url.startsWith(prefix)) {
      return null;
    }

    final fileName = url.substring(prefix.length);
    if (fileName.isEmpty || fileName.contains('/') || fileName.contains('\\')) {
      return null;
    }

    final wallpaperDir = await AppSettings.resolveWallpaperDirectory();
    return File(p.join(wallpaperDir.path, fileName));
  }

  String _resolveExtension(String filename, String? contentType) {
    final fileExtension = p.extension(filename);
    if (fileExtension.isNotEmpty) {
      return fileExtension.toLowerCase();
    }

    final mimeType = contentType?.split(';').first.trim().toLowerCase();
    final extension = mimeType == null ? null : extensionFromMime(mimeType);
    if (extension == null || extension.isEmpty) {
      return '';
    }

    return '.${extension.toLowerCase()}';
  }

  String? _resolveCustomType(String? contentType, String filename) {
    final mimeType =
        (contentType?.split(';').first.trim().toLowerCase() ??
                lookupMimeType(filename) ??
                '')
            .toLowerCase();
    if (mimeType.startsWith('image/')) {
      return 'image';
    }
    if (mimeType.startsWith('video/')) {
      return 'video';
    }

    return null;
  }
}
