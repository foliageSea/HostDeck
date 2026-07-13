import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/digests/sha256.dart';
import 'package:shelf/shelf.dart';

class AccessPrincipal {
  final String id;
  final String type;

  const AccessPrincipal({required this.id, required this.type});
}

class AccessAuthService {
  static const cookieName = 'hostdeck_session';
  static const principalContextKey = 'hostdeck.accessPrincipal';

  final String? _password;
  final String? _apiToken;
  final Duration sessionTtl;
  final bool secureCookies;
  final Random _random;
  final Map<String, DateTime> _sessions = {};

  AccessAuthService({
    String? password,
    String? apiToken,
    this.sessionTtl = const Duration(hours: 12),
    this.secureCookies = false,
    Random? random,
  }) : _password = _normalize(password),
       _apiToken = _normalize(apiToken),
       _random = random ?? Random.secure();

  bool get enabled => _password != null || _apiToken != null;
  bool get passwordLoginEnabled => _password != null;

  String createSession(String password) {
    if (_password == null || !_constantTimeEquals(password, _password)) {
      throw const AccessDeniedException();
    }

    _removeExpiredSessions();
    final token = _randomToken();
    _sessions[token] = DateTime.now().toUtc().add(sessionTtl);
    return token;
  }

  void revokeSession(String? token) {
    if (token != null) {
      _sessions.remove(token);
    }
  }

  AccessPrincipal? authenticate(Request request) {
    if (!enabled) {
      return const AccessPrincipal(id: 'local', type: 'local');
    }

    final authorization = request.headers['authorization'];
    if (authorization != null && authorization.startsWith('Bearer ')) {
      final token = authorization.substring('Bearer '.length).trim();
      if (_apiToken != null && _constantTimeEquals(token, _apiToken)) {
        return const AccessPrincipal(id: 'api-token', type: 'apiToken');
      }
    }

    final sessionToken = sessionTokenFromRequest(request);
    if (sessionToken == null) {
      return null;
    }

    final expiresAt = _sessions[sessionToken];
    if (expiresAt == null || !expiresAt.isAfter(DateTime.now().toUtc())) {
      _sessions.remove(sessionToken);
      return null;
    }

    return AccessPrincipal(id: sessionToken, type: 'browserSession');
  }

  String? sessionTokenFromRequest(Request request) {
    final cookieHeader = request.headers['cookie'];
    if (cookieHeader == null) {
      return null;
    }

    for (final part in cookieHeader.split(';')) {
      final separator = part.indexOf('=');
      if (separator <= 0) {
        continue;
      }
      if (part.substring(0, separator).trim() == cookieName) {
        return part.substring(separator + 1).trim();
      }
    }
    return null;
  }

  String sessionCookie(String token, {required bool secure}) {
    final attributes = <String>[
      '$cookieName=$token',
      'Path=/',
      'HttpOnly',
      'SameSite=Strict',
      'Max-Age=${sessionTtl.inSeconds}',
      if (secure) 'Secure',
    ];
    return attributes.join('; ');
  }

  String expiredSessionCookie({required bool secure}) {
    final attributes = <String>[
      '$cookieName=',
      'Path=/',
      'HttpOnly',
      'SameSite=Strict',
      'Max-Age=0',
      if (secure) 'Secure',
    ];
    return attributes.join('; ');
  }

  void _removeExpiredSessions() {
    final now = DateTime.now().toUtc();
    _sessions.removeWhere((_, expiresAt) => !expiresAt.isAfter(now));
  }

  String _randomToken() {
    final bytes = List<int>.generate(32, (_) => _random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  static String? _normalize(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  static bool _constantTimeEquals(String value, String expected) {
    final digest = SHA256Digest();
    final valueHash = digest.process(Uint8List.fromList(utf8.encode(value)));
    final expectedHash = digest.process(
      Uint8List.fromList(utf8.encode(expected)),
    );
    var difference = 0;
    for (var i = 0; i < valueHash.length; i++) {
      difference |= valueHash[i] ^ expectedHash[i];
    }
    return difference == 0;
  }
}

class AccessDeniedException implements Exception {
  const AccessDeniedException();
}
