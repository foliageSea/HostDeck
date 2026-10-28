import 'dart:io';

import 'package:logging/logging.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf_static/shelf_static.dart';

import 'package:host_deck/server/routes/api_routes.dart';
import 'package:host_deck/server/core/ssh/ssh_service.dart';
import 'package:host_deck/server/features/access/access_middleware.dart';
import 'package:host_deck/server/features/access/access_auth_service.dart';
import 'package:host_deck/server/features/operation_logs/operation_log_middleware.dart';
import 'package:host_deck/server/features/operation_logs/operation_log_service.dart';
import 'package:host_deck/server/features/port_forwards/port_forward_repository.dart';
import 'package:host_deck/server/features/servers/server_repository.dart';
import 'package:host_deck/utils/app_settings.dart';

Middleware accessLogMiddleware(Logger log) {
  return (innerHandler) {
    return (request) async {
      final stopwatch = Stopwatch()..start();
      try {
        final response = await innerHandler(request);
        stopwatch.stop();
        final message = formatAccessLog(
          request,
          response.statusCode,
          stopwatch.elapsed,
        );
        if (response.statusCode >= 500) {
          log.severe(message);
        } else if (response.statusCode >= 400) {
          log.warning(message);
        } else {
          log.info(message);
        }
        return response;
      } on HijackException {
        rethrow;
      } catch (error, stackTrace) {
        stopwatch.stop();
        log.severe(
          formatAccessLog(request, 500, stopwatch.elapsed),
          error,
          stackTrace,
        );
        rethrow;
      }
    };
  };
}

/// 任何携带 connectionId 的 HTTP 请求都视为「这条 SSH 连接还在被使用」。
///
/// 浏览器的状态 WebSocket 可能静默失效（TCP 还挂着但收不到数据），而页面
/// 本身仍在发请求；空闲回收器必须把这类活动算进去，否则会误杀会话。
Middleware sshActivityMiddleware(SshService sshService) {
  return (innerHandler) {
    return (request) {
      final connectionId = request.url.queryParameters['connectionId'];
      if (connectionId != null && connectionId.isNotEmpty) {
        sshService.touch(connectionId);
      }
      return innerHandler(request);
    };
  };
}

String formatAccessLog(Request request, int statusCode, Duration elapsed) {
  final path = request.url.path.isEmpty ? '/' : '/${request.url.path}';
  final query = request.url.hasQuery ? ' | ${request.url.query}' : '';
  return '${request.method} $path $statusCode ${elapsed.inMilliseconds}ms$query';
}

Future<Handler> buildServerHandler({
  required ApiRoutes apiRoutes,
  required SshService sshService,
  required String staticPath,
  required Logger log,
  required AccessAuthService accessService,
  required OperationLogService operationLogService,
  required PortForwardRepository portForwardRepository,
  required ServerRepository serverRepository,
}) async {
  Handler? staticHandler;
  final wallpaperDir = await AppSettings.resolveWallpaperDirectory();
  if (staticPath.isNotEmpty) {
    staticHandler = createStaticHandler(
      staticPath,
      defaultDocument: 'index.html',
    );
  }

  Response spaFallback(Request request) {
    if (request.url.path.startsWith('api/')) {
      return Response.notFound('API Route not found');
    }
    if (staticPath.isNotEmpty) {
      final indexFile = File('$staticPath/index.html');
      if (indexFile.existsSync()) {
        return Response.ok(
          indexFile.readAsBytesSync(),
          headers: {'content-type': 'text/html'},
        );
      }
    }
    return Response.notFound('Not found');
  }

  Future<Response?> serveWallpaper(Request request) async {
    if (!request.url.path.startsWith('wallpapers/')) {
      return null;
    }

    final relativePath = request.url.path.substring('wallpapers/'.length);
    if (relativePath.isEmpty ||
        p.isAbsolute(relativePath) ||
        relativePath.contains('/') ||
        relativePath.contains(r'\')) {
      return Response.notFound('Not found');
    }

    final file = File(p.join(wallpaperDir.path, relativePath));
    if (!await file.exists()) {
      return Response.notFound('Not found');
    }

    final mimeType = lookupMimeType(file.path) ?? 'application/octet-stream';
    return Response.ok(
      file.openRead(),
      headers: {
        'content-type': mimeType,
        'cache-control': 'public, max-age=31536000, immutable',
      },
    );
  }

  final apiHandler = operationLogMiddleware(
    operationLogService,
    serverRepository,
    portForwardRepository,
  )(accessMiddleware(accessService)(apiRoutes.router.call));
  var cascade = Cascade().add(apiHandler);
  cascade = cascade.add((request) async {
    return await serveWallpaper(request) ?? Response.notFound('Not found');
  });

  if (staticHandler != null) {
    cascade = cascade.add(staticHandler);
  }

  cascade = cascade.add(spaFallback);

  return Pipeline()
      .addMiddleware(accessLogMiddleware(log))
      .addMiddleware(sshActivityMiddleware(sshService))
      .addHandler(cascade.handler);
}
