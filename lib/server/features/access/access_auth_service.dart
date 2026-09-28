import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';
import 'package:shelf/shelf.dart';

import 'package:host_deck/server/features/access/access_secret_store.dart';

class AccessPrincipal {
  final String id;
  final String type;

  const AccessPrincipal({required this.id, required this.type});
}

class TotpSetup {
  final String secret;
  final String provisioningUri;
  final List<String> recoveryCodes;

  const TotpSetup({
    required this.secret,
    required this.provisioningUri,
    required this.recoveryCodes,
  });

  Map<String, dynamic> toJson() => {
    'secret': secret,
    'provisioningUri': provisioningUri,
    'recoveryCodes': recoveryCodes,
  };
}

class AccessAuthService {
  static const cookieName = 'hostdeck_session';
  static const principalContextKey = 'hostdeck.accessPrincipal';

  final String? _password;
  final String? _apiToken;
  final String? _environmentTotpSecret;
  final AccessSecretStore? _secretStore;
  final Duration sessionTtl;
  final bool secureCookies;
  final String totpIssuer;
  final String totpAccount;
  final Random _random;
  final DateTime Function() _now;
  final Map<String, DateTime> _sessions = {};
  final Map<String, _LoginAttemptState> _loginAttempts = {};
  _PendingTotpSetup? _pendingTotpSetup;

  AccessAuthService({
    String? password,
    String? apiToken,
    String? totpSecret,
    AccessSecretStore? secretStore,
    this.sessionTtl = const Duration(hours: 12),
    this.secureCookies = false,
    this.totpIssuer = 'HostDeck',
    this.totpAccount = 'Administrator',
    Random? random,
    DateTime Function()? now,
  }) : _password = _normalize(password),
       _apiToken = _normalize(apiToken),
       _environmentTotpSecret = _normalizeTotpSecret(totpSecret),
       _secretStore = secretStore,
       _random = random ?? Random.secure(),
       _now = now ?? (() => DateTime.now().toUtc()) {
    final configuredSecrets = <String?>[
      _environmentTotpSecret,
      _secretStore?.totpSecret,
    ];
    for (final secret in configuredSecrets) {
      if (secret != null) Totp.base32Decode(secret);
    }
  }

  String? get _totpSecret =>
      _normalizeTotpSecret(_secretStore?.totpSecret) ?? _environmentTotpSecret;

  bool get enabled =>
      _password != null || _apiToken != null || _totpSecret != null;

  bool get passwordLoginEnabled => _password != null;

  bool get totpLoginEnabled => _totpSecret != null;

  String get totpSource {
    if (_secretStore?.totpSecret != null) return 'stored';
    if (_environmentTotpSecret != null) return 'environment';
    return 'none';
  }

  int get recoveryCodesRemaining => _secretStore?.recoveryCodesRemaining ?? 0;

  String createSession(String password) {
    if (_password == null || !_constantTimeEquals(password, _password)) {
      throw const AccessDeniedException();
    }
    return _issueSession();
  }

  Future<String> createTotpSession(String code) async {
    if (!totpLoginEnabled || !await verifyTotpOrRecoveryCode(code)) {
      throw const AccessDeniedException();
    }
    return _issueSession();
  }

  String createSessionAfterTotpSetup() => _issueSession();

  bool verifyCurrentTotpCode(String code) {
    final secret = _totpSecret;
    if (secret == null) return false;
    return Totp.verify(secret: secret, code: code, time: _now());
  }

  Future<bool> verifyTotpOrRecoveryCode(String credential) async {
    if (verifyCurrentTotpCode(credential.trim())) return true;

    final store = _secretStore;
    if (store == null) return false;
    final normalized = _normalizeRecoveryCode(credential);
    if (normalized.length < 12) return false;
    return store.consumeRecoveryCodeHash(_hashRecoveryCode(normalized));
  }

  Future<TotpSetup> beginTotpSetup({String? currentCode}) async {
    final store = _requireSecretStore();
    if (totpLoginEnabled) {
      final value = currentCode?.trim() ?? '';
      if (value.isEmpty || !await verifyTotpOrRecoveryCode(value)) {
        throw const AccessDeniedException();
      }
    }

    final secret = Totp.generateSecret(random: _random);
    final recoveryCodes = List<String>.generate(
      8,
      (_) => _generateRecoveryCode(),
      growable: false,
    );
    _pendingTotpSetup = _PendingTotpSetup(
      secret: secret,
      recoveryCodes: recoveryCodes,
      expiresAt: _now().add(const Duration(minutes: 10)),
    );

    final label = Uri.encodeComponent('$totpIssuer:$totpAccount');
    final query = Uri(
      queryParameters: {
        'secret': secret,
        'issuer': totpIssuer,
        'algorithm': 'SHA1',
        'digits': '6',
        'period': '30',
      },
    ).query;

    // Touch the store after initialization so setup cannot run in a partial state.
    store.recoveryCodesRemaining;
    return TotpSetup(
      secret: secret,
      provisioningUri: 'otpauth://totp/$label?$query',
      recoveryCodes: List.unmodifiable(recoveryCodes),
    );
  }

  Future<TotpSetup> confirmTotpSetup(String code) async {
    final pending = _pendingTotpSetup;
    if (pending == null || !pending.expiresAt.isAfter(_now())) {
      _pendingTotpSetup = null;
      throw const AccessSetupExpiredException();
    }
    if (!Totp.verify(secret: pending.secret, code: code, time: _now())) {
      throw const AccessDeniedException();
    }

    final store = _requireSecretStore();
    await store.saveTotp(
      secret: pending.secret,
      recoveryCodeHashes: pending.recoveryCodes
          .map((code) => _hashRecoveryCode(_normalizeRecoveryCode(code)))
          .toList(growable: false),
    );
    _pendingTotpSetup = null;
    return TotpSetup(
      secret: pending.secret,
      provisioningUri: '',
      recoveryCodes: List.unmodifiable(pending.recoveryCodes),
    );
  }

  Future<void> disableTotp(String code) async {
    if (_secretStore?.totpSecret == null && _environmentTotpSecret != null) {
      throw const AccessConfigurationException(
        'Environment-managed TOTP cannot be disabled from the application.',
      );
    }
    if (!totpLoginEnabled || !await verifyTotpOrRecoveryCode(code)) {
      throw const AccessDeniedException();
    }
    await _requireSecretStore().clearTotp();
    _pendingTotpSetup = null;
  }

  bool isLoginRateLimited(String key) {
    final state = _loginAttempts[key];
    if (state == null) return false;
    final now = _now();
    if (state.blockedUntil != null && state.blockedUntil!.isAfter(now)) {
      return true;
    }
    if (state.firstFailure.add(const Duration(minutes: 1)).isBefore(now)) {
      _loginAttempts.remove(key);
    }
    return false;
  }

  void recordLoginFailure(String key) {
    final now = _now();
    final current = _loginAttempts[key];
    if (current == null ||
        current.firstFailure.add(const Duration(minutes: 1)).isBefore(now)) {
      _loginAttempts[key] = _LoginAttemptState(firstFailure: now, failures: 1);
      return;
    }

    current.failures++;
    if (current.failures >= 5) {
      current.blockedUntil = now.add(const Duration(minutes: 5));
    }
  }

  void recordLoginSuccess(String key) {
    _loginAttempts.remove(key);
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
    if (expiresAt == null || !expiresAt.isAfter(_now())) {
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

  String _issueSession() {
    _removeExpiredSessions();
    final token = _randomToken();
    _sessions[token] = _now().add(sessionTtl);
    return token;
  }

  void _removeExpiredSessions() {
    final now = _now();
    _sessions.removeWhere((_, expiresAt) => !expiresAt.isAfter(now));
  }

  String _randomToken() {
    final bytes = List<int>.generate(32, (_) => _random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  String _generateRecoveryCode() {
    final bytes = Uint8List.fromList(
      List<int>.generate(10, (_) => _random.nextInt(256)),
    );
    final value = Totp.base32Encode(bytes);
    return '${value.substring(0, 4)}-${value.substring(4, 8)}-'
        '${value.substring(8, 12)}-${value.substring(12, 16)}';
  }

  AccessSecretStore _requireSecretStore() {
    final store = _secretStore;
    if (store == null) {
      throw const AccessConfigurationException(
        'Persistent access secret storage is unavailable.',
      );
    }
    return store;
  }

  static String? _normalize(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  static String? _normalizeTotpSecret(String? value) {
    final normalized = value?.toUpperCase().replaceAll(RegExp(r'[\s=-]'), '');
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  static String _normalizeRecoveryCode(String value) =>
      value.toUpperCase().replaceAll(RegExp(r'[^A-Z2-7]'), '');

  static String _hashRecoveryCode(String value) {
    final digest = SHA256Digest().process(
      Uint8List.fromList(utf8.encode(value)),
    );
    return base64Url.encode(digest).replaceAll('=', '');
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

class Totp {
  static const _alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

  static bool verify({
    required String secret,
    required String code,
    required DateTime time,
    int window = 1,
  }) {
    final normalizedCode = code.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(normalizedCode)) return false;

    for (var offset = -window; offset <= window; offset++) {
      final candidate = generate(
        secret: secret,
        time: time.add(Duration(seconds: offset * 30)),
      );
      if (_constantTimeCodeEquals(candidate, normalizedCode)) return true;
    }
    return false;
  }

  static String generate({
    required String secret,
    required DateTime time,
    int digits = 6,
    int period = 30,
  }) {
    final key = base32Decode(secret);
    final counter = time.toUtc().millisecondsSinceEpoch ~/ 1000 ~/ period;
    final counterBytes = Uint8List(8);
    var value = counter;
    for (var i = counterBytes.length - 1; i >= 0; i--) {
      counterBytes[i] = value & 0xff;
      value >>= 8;
    }

    final digest = HMac(SHA1Digest(), 64)..init(KeyParameter(key));
    final hash = digest.process(counterBytes);
    final offset = hash.last & 0x0f;
    final binary =
        ((hash[offset] & 0x7f) << 24) |
        ((hash[offset + 1] & 0xff) << 16) |
        ((hash[offset + 2] & 0xff) << 8) |
        (hash[offset + 3] & 0xff);
    final modulus = pow(10, digits).toInt();
    return (binary % modulus).toString().padLeft(digits, '0');
  }

  static String generateSecret({Random? random}) {
    final generator = random ?? Random.secure();
    final bytes = Uint8List.fromList(
      List<int>.generate(20, (_) => generator.nextInt(256)),
    );
    return base32Encode(bytes);
  }

  static String base32Encode(Uint8List bytes) {
    final output = StringBuffer();
    var buffer = 0;
    var bits = 0;
    for (final byte in bytes) {
      buffer = (buffer << 8) | byte;
      bits += 8;
      while (bits >= 5) {
        bits -= 5;
        output.write(_alphabet[(buffer >> bits) & 31]);
      }
    }
    if (bits > 0) {
      output.write(_alphabet[(buffer << (5 - bits)) & 31]);
    }
    return output.toString();
  }

  static Uint8List base32Decode(String value) {
    final normalized = value.toUpperCase().replaceAll(RegExp(r'[\s=-]'), '');
    final output = <int>[];
    var buffer = 0;
    var bits = 0;
    for (final rune in normalized.runes) {
      final index = _alphabet.indexOf(String.fromCharCode(rune));
      if (index < 0) throw const FormatException('Invalid Base32 secret.');
      buffer = (buffer << 5) | index;
      bits += 5;
      if (bits >= 8) {
        bits -= 8;
        output.add((buffer >> bits) & 0xff);
      }
    }
    if (output.length < 10) {
      throw const FormatException('Base32 secret is too short.');
    }
    return Uint8List.fromList(output);
  }

  static bool _constantTimeCodeEquals(String value, String expected) {
    if (value.length != expected.length) return false;
    var difference = 0;
    for (var i = 0; i < value.length; i++) {
      difference |= value.codeUnitAt(i) ^ expected.codeUnitAt(i);
    }
    return difference == 0;
  }
}

class _PendingTotpSetup {
  final String secret;
  final List<String> recoveryCodes;
  final DateTime expiresAt;

  const _PendingTotpSetup({
    required this.secret,
    required this.recoveryCodes,
    required this.expiresAt,
  });
}

class _LoginAttemptState {
  final DateTime firstFailure;
  int failures;
  DateTime? blockedUntil;

  _LoginAttemptState({required this.firstFailure, required this.failures});
}

class AccessDeniedException implements Exception {
  const AccessDeniedException();
}

class AccessSetupExpiredException implements Exception {
  const AccessSetupExpiredException();
}

class AccessConfigurationException implements Exception {
  final String message;

  const AccessConfigurationException(this.message);
}
