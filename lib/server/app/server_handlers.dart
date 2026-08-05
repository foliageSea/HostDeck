import 'dart:io';

import 'package:logging/logging.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf_static/shelf_static.dart';

import 'package:host_deck/server/routes/api_routes.dart';
import 'package:host_deck/server/features/access/access_middleware.dart';
import 'package:host_deck/server/features/access/access_auth_service.dart';
import 'package:host_deck/server/features/operation_logs/operation_log_middleware.dart';
import 'package:host_deck/server/features/operation_logs/operation_log_service.dart';
import 'package:host_deck/server/features/port_forwards/port_forward_repository.dart';
import 'package:host_deck/server/features/servers/server_repository.dart';
import 'package:host_deck/utils/app_settings.dart';

Future<Handler> buildServerHandler({
  required ApiRoutes apiRoutes,
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
      .addMiddleware(
        logRequests(
          logger: (message, isError) {
            if (isError) {
              log.severe(message);
            } else {
              log.info(message);
            }
          },
        ),
      )
      .addHandler(cascade.handler);
}
