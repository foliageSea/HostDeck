import 'dart:convert';

import 'package:shelf/shelf.dart';

import 'package:host_deck/server/core/http/result.dart';
import 'package:host_deck/server/features/access/access_auth_service.dart';

class AccessController {
  final AccessAuthService authService;

  AccessController(this.authService);

  Response state(Request request) {
    final principal = authService.authenticate(request);
    return Result.ok({
      'enabled': authService.enabled,
      'passwordLoginEnabled': authService.passwordLoginEnabled,
      'authenticated': principal != null,
      'principalType': principal?.type,
    });
  }

  Future<Response> login(Request request) async {
    if (!authService.enabled) {
      return Result.ok({'authenticated': true});
    }
    if (!authService.passwordLoginEnabled) {
      return _jsonError(403, 'Password login is not enabled');
    }

    try {
      final body = jsonDecode(await request.readAsString());
      final password = body is Map<String, dynamic> ? body['password'] : null;
      if (password is! String || password.isEmpty) {
        return _jsonError(400, 'Password is required');
      }

      final token = authService.createSession(password);
      return Result.ok({'authenticated': true}).change(
        headers: {
          'set-cookie': authService.sessionCookie(
            token,
            secure:
                authService.secureCookies ||
                request.requestedUri.scheme == 'https',
          ),
        },
      );
    } on AccessDeniedException {
      return _jsonError(401, 'Invalid password');
    } on FormatException {
      return _jsonError(400, 'Invalid JSON body');
    }
  }

  Response logout(Request request) {
    authService.revokeSession(authService.sessionTokenFromRequest(request));
    return Result.ok({'authenticated': false}).change(
      headers: {
        'set-cookie': authService.expiredSessionCookie(
          secure:
              authService.secureCookies ||
              request.requestedUri.scheme == 'https',
        ),
      },
    );
  }

  Response _jsonError(int status, String message) {
    return Response(
      status,
      body: jsonEncode({'code': status, 'message': message, 'data': null}),
      headers: {'content-type': 'application/json'},
    );
  }
}
