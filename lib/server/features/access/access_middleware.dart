import 'dart:convert';

import 'package:shelf/shelf.dart';

import 'package:host_deck/server/features/access/access_auth_service.dart';

Middleware accessMiddleware(AccessAuthService authService) {
  return (innerHandler) {
    return (request) {
      final path = request.url.path;
      if (!path.startsWith('api/')) {
        return innerHandler(request);
      }

      final isPublic =
          path == 'api/status' ||
          path == 'api/agent/discovery' ||
          path == 'api/access/state' ||
          path == 'api/access/login';
      final principal = authService.authenticate(request);

      if (authService.enabled && principal == null && !isPublic) {
        return Response(
          401,
          body: jsonEncode({
            'code': 401,
            'message': 'Authentication required',
            'data': null,
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      if (principal?.type == 'browserSession' &&
          _requiresOriginCheck(request, path) &&
          !_hasSameOrigin(request)) {
        return Response(
          403,
          body: jsonEncode({
            'code': 403,
            'message': 'Invalid request origin',
            'data': null,
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      return innerHandler(
        request.change(
          context: {AccessAuthService.principalContextKey: principal},
        ),
      );
    };
  };
}

bool _requiresOriginCheck(Request request, String path) {
  return path.startsWith('api/ws/') ||
      request.method == 'POST' ||
      request.method == 'PUT' ||
      request.method == 'PATCH' ||
      request.method == 'DELETE';
}

bool _hasSameOrigin(Request request) {
  final origin = request.headers['origin'];
  final host = request.headers['host'];
  if (origin == null || host == null) {
    return false;
  }

  final originUri = Uri.tryParse(origin);
  if (originUri == null ||
      (originUri.scheme != 'http' && originUri.scheme != 'https')) {
    return false;
  }
  return originUri.authority.toLowerCase() == host.toLowerCase();
}
