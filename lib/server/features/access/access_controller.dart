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
      'totpLoginEnabled': authService.totpLoginEnabled,
      'totpSource': authService.totpSource,
      'totpIssuer': authService.totpIssuer,
      'totpAccount': authService.totpAccount,
      'recoveryCodesRemaining': authService.recoveryCodesRemaining,
      'authenticated': principal != null,
      'principalType': principal?.type,
    });
  }

  Future<Response> login(Request request) async {
    if (!authService.enabled) {
      return Result.ok({'authenticated': true});
    }
    final rateLimitKey = _loginRateLimitKey(request);
    if (authService.isLoginRateLimited(rateLimitKey)) {
      return _jsonError(429, 'Too many login attempts. Try again later.');
    }

    try {
      final body = jsonDecode(await request.readAsString());
      if (body is! Map<String, dynamic>) {
        return _jsonError(400, 'Invalid JSON body');
      }

      final password = body['password'];
      final code = body['code'];
      final String token;
      if (password is String && password.isNotEmpty) {
        token = authService.createSession(password);
      } else if (code is String && code.trim().isNotEmpty) {
        token = await authService.createTotpSession(code);
      } else {
        return _jsonError(400, 'Password or authenticator code is required');
      }

      authService.recordLoginSuccess(rateLimitKey);
      return Result.ok({
        'authenticated': true,
      }).change(headers: _sessionHeaders(request, token));
    } on AccessDeniedException {
      authService.recordLoginFailure(rateLimitKey);
      return _jsonError(401, 'Invalid access credential');
    } on FormatException {
      return _jsonError(400, 'Invalid JSON body');
    }
  }

  Future<Response> beginTotpSetup(Request request) async {
    try {
      final body = await _readObject(request);
      final currentCode = body['currentCode'];
      if (currentCode != null && currentCode is! String) {
        return _jsonError(400, 'Invalid current authenticator code');
      }

      final setup = await authService.beginTotpSetup(
        currentCode: currentCode as String?,
      );
      return Result.ok(setup.toJson());
    } on AccessDeniedException {
      return _jsonError(401, 'Invalid authenticator code');
    } on AccessConfigurationException catch (error) {
      return _jsonError(503, error.message);
    } on FormatException {
      return _jsonError(400, 'Invalid JSON body');
    }
  }

  Future<Response> confirmTotpSetup(Request request) async {
    try {
      final body = await _readObject(request);
      final code = body['code'];
      if (code is! String || code.trim().isEmpty) {
        return _jsonError(400, 'Authenticator code is required');
      }

      final setup = await authService.confirmTotpSetup(code);
      final token = authService.createSessionAfterTotpSetup();
      return Result.ok(
        setup.toJson(),
      ).change(headers: _sessionHeaders(request, token));
    } on AccessDeniedException {
      return _jsonError(401, 'Invalid authenticator code');
    } on AccessSetupExpiredException {
      return _jsonError(410, 'Authenticator setup has expired');
    } on AccessConfigurationException catch (error) {
      return _jsonError(503, error.message);
    } on FormatException {
      return _jsonError(400, 'Invalid JSON body');
    }
  }

  Future<Response> disableTotp(Request request) async {
    try {
      final body = await _readObject(request);
      final code = body['code'];
      if (code is! String || code.trim().isEmpty) {
        return _jsonError(400, 'Authenticator code is required');
      }

      await authService.disableTotp(code);
      return Result.ok({'totpLoginEnabled': authService.totpLoginEnabled});
    } on AccessDeniedException {
      return _jsonError(401, 'Invalid authenticator code');
    } on AccessConfigurationException catch (error) {
      return _jsonError(409, error.message);
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

  Future<Map<String, dynamic>> _readObject(Request request) async {
    final body = jsonDecode(await request.readAsString());
    if (body is! Map) throw const FormatException('Expected JSON object');
    return body.map((key, value) => MapEntry(key.toString(), value));
  }

  Map<String, String> _sessionHeaders(Request request, String token) => {
    'set-cookie': authService.sessionCookie(
      token,
      secure:
          authService.secureCookies || request.requestedUri.scheme == 'https',
    ),
  };

  String _loginRateLimitKey(Request request) =>
      request.headers['x-forwarded-for']?.split(',').first.trim() ??
      request.headers['x-real-ip'] ??
      'global';

  Response _jsonError(int status, String message) {
    return Response(
      status,
      body: jsonEncode({'code': status, 'message': message, 'data': null}),
      headers: {'content-type': 'application/json'},
    );
  }
}
