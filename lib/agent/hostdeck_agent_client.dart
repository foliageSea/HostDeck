import 'dart:convert';
import 'dart:io';

import 'package:host_deck/utils/hostdeck_discovery.dart';
import 'package:crypto/crypto.dart';

/// Result of resolving which HostDeck server to talk to.
class HostDeckAgentDiscovery {
  final String baseUrl;
  final String source;
  final String? instanceFile;

  const HostDeckAgentDiscovery({
    required this.baseUrl,
    required this.source,
    this.instanceFile,
  });

  Map<String, dynamic> toJson() => {
    'baseUrl': baseUrl,
    'source': source,
    'instanceFile': instanceFile,
  };
}

/// Result of probing a HostDeck server's agent discovery endpoint.
class HostDeckAgentProbe {
  final bool ok;
  final String message;
  final Object? data;

  const HostDeckAgentProbe({
    required this.ok,
    required this.message,
    required this.data,
  });
}

/// Shared HTTP client for the HostDeck agent API.
///
/// Used by both `bin/hostdeck_cli.dart` and the MCP server so that discovery,
/// authentication and response handling stay consistent.
class HostDeckAgentClient {
  static const String defaultBaseUrl = 'http://127.0.0.1:8080';

  final String? _explicitBaseUrl;
  final String? _token;
  final HttpClient Function()? _httpClientFactory;
  final String? _trustedCertificatePath;

  HostDeckAgentClient({
    String? baseUrl,
    String? token,
    String? trustedCertificatePath,
  }) : _explicitBaseUrl = _normalize(baseUrl),
       _token = _normalize(token),
       _httpClientFactory = null,
       _trustedCertificatePath =
           trustedCertificatePath ?? Platform.environment['HOSTDECK_CA_CERT'];

  /// Test hook that allows injecting a custom [HttpClient] factory.
  HostDeckAgentClient.withFactory({
    String? baseUrl,
    String? token,
    required HttpClient Function() httpClientFactory,
  }) : _explicitBaseUrl = _normalize(baseUrl),
       _token = _normalize(token),
       _httpClientFactory = httpClientFactory,
       _trustedCertificatePath = null;

  static String? _normalize(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  static String? tokenFromEnvironment() =>
      _normalize(Platform.environment['HOSTDECK_TOKEN']);

  /// Resolves the HostDeck base URL in the same order as the CLI:
  /// explicit option > HOSTDECK_URL > instance file > default.
  Future<HostDeckAgentDiscovery> resolveBaseUrl() async {
    final explicit = _explicitBaseUrl;
    if (explicit != null) {
      return HostDeckAgentDiscovery(baseUrl: explicit, source: 'option');
    }

    final envUrl = _normalize(
      Platform.environment[HostDeckDiscovery.envUrlKey],
    );
    if (envUrl != null) {
      return HostDeckAgentDiscovery(baseUrl: envUrl, source: 'env');
    }

    final instanceFile = await HostDeckDiscovery.instanceFile();
    try {
      final instance = await HostDeckDiscovery.readInstance();
      final baseUrl = instance?['baseUrl'];
      if (baseUrl is String && baseUrl.isNotEmpty) {
        final probe = await this.probe(baseUrl);
        if (probe.ok) {
          return HostDeckAgentDiscovery(
            baseUrl: baseUrl,
            source: 'instance-file',
            instanceFile: instanceFile.path,
          );
        }
      }
    } catch (_) {
      // Ignore stale or invalid discovery files and fall back to the default.
    }

    return HostDeckAgentDiscovery(
      baseUrl: defaultBaseUrl,
      source: 'default',
      instanceFile: instanceFile.path,
    );
  }

  /// Probes `GET /api/agent/discovery` to verify the server is HostDeck.
  Future<HostDeckAgentProbe> probe(String baseUrl) async {
    try {
      final result = await get(baseUrl, '/api/agent/discovery');
      final data = result['data'];
      final ok =
          result['code'] == 200 &&
          data is Map &&
          data['name'] == 'HostDeck' &&
          data['agentApi'] == true;
      return HostDeckAgentProbe(
        ok: ok,
        message: ok ? 'success' : (result['message']?.toString() ?? 'failed'),
        data: data,
      );
    } catch (e) {
      return HostDeckAgentProbe(ok: false, message: e.toString(), data: null);
    }
  }

  /// Runs the discovery flow and reports the resolved endpoint plus probe.
  Future<Map<String, dynamic>> discover() async {
    final discovery = await resolveBaseUrl();
    final probeResult = await probe(discovery.baseUrl);
    return {
      'code': probeResult.ok ? 200 : 503,
      'message': probeResult.ok ? 'success' : probeResult.message,
      'data': {
        'baseUrl': discovery.baseUrl,
        'source': discovery.source,
        'instanceFile': discovery.instanceFile,
        'probe': probeResult.data,
      },
    };
  }

  Future<Map<String, dynamic>> listSessions() async {
    final baseUrl = (await resolveBaseUrl()).baseUrl;
    return get(baseUrl, '/api/agent/sessions');
  }

  Future<Map<String, dynamic>> exec({
    required String connectionId,
    required String command,
    String? cwd,
    int? timeoutMs,
    int? maxOutputBytes,
  }) async {
    final baseUrl = (await resolveBaseUrl()).baseUrl;
    return post(baseUrl, '/api/agent/exec', {
      'connectionId': connectionId,
      'command': command,
      'cwd': ?cwd,
      'timeoutMs': ?timeoutMs,
      'maxOutputBytes': ?maxOutputBytes,
    });
  }

  Future<Map<String, dynamic>> readFile({
    required String connectionId,
    required String path,
  }) async {
    final baseUrl = (await resolveBaseUrl()).baseUrl;
    return post(baseUrl, '/api/agent/file/read', {
      'connectionId': connectionId,
      'path': path,
    });
  }

  Future<Map<String, dynamic>> writeFile({
    required String connectionId,
    required String path,
    required String content,
  }) async {
    final baseUrl = (await resolveBaseUrl()).baseUrl;
    return post(baseUrl, '/api/agent/file/write', {
      'connectionId': connectionId,
      'path': path,
      'content': content,
    });
  }

  Future<Map<String, dynamic>> applyPatch({
    required String connectionId,
    required String patch,
    String? cwd,
    int? timeoutMs,
  }) async {
    final baseUrl = (await resolveBaseUrl()).baseUrl;
    return post(baseUrl, '/api/agent/patch', {
      'connectionId': connectionId,
      'patch': patch,
      'cwd': ?cwd,
      'timeoutMs': ?timeoutMs,
    });
  }

  Future<Map<String, dynamic>> get(String baseUrl, String path) async {
    final client = await _createClient(baseUrl);
    try {
      final uri = Uri.parse(baseUrl).resolve(path);
      final request = await client.getUrl(uri);
      _addAuthorization(request);

      final response = await request.close();
      final text = await response.transform(utf8.decoder).join();
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }

      return {
        'code': response.statusCode,
        'message': 'Invalid response',
        'data': text,
      };
    } finally {
      client.close(force: true);
    }
  }

  Future<Map<String, dynamic>> post(
    String baseUrl,
    String path,
    Map<String, dynamic> body,
  ) async {
    final client = await _createClient(baseUrl);
    try {
      final uri = Uri.parse(baseUrl).resolve(path);
      final request = await client.postUrl(uri);
      _addAuthorization(request);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));

      final response = await request.close();
      final text = await response.transform(utf8.decoder).join();
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }

      return {
        'code': response.statusCode,
        'message': 'Invalid response',
        'data': text,
      };
    } finally {
      client.close(force: true);
    }
  }

  Future<HttpClient> _createClient(String baseUrl) async {
    if (_httpClientFactory != null) return _httpClientFactory();
    final context = SecurityContext(withTrustedRoots: true);
    final trustedPath = _trustedCertificatePath;
    if (trustedPath != null) {
      context.setTrustedCertificatesBytes(
        await File(trustedPath).readAsBytes(),
      );
    }
    final client = HttpClient(context: context);
    final uri = Uri.parse(baseUrl);
    // Only the local discovery file can opt a loopback endpoint into pinning.
    // Explicit remote URLs continue to use normal CA and hostname validation.
    if (uri.scheme == 'https' &&
        ['127.0.0.1', '::1', 'localhost'].contains(uri.host) &&
        trustedPath == null) {
      try {
        final instance = await HostDeckDiscovery.readInstance();
        final pem = instance?['certificatePem'];
        if (instance?['baseUrl'] == baseUrl && pem is String) {
          final match = RegExp(
            r'-----BEGIN CERTIFICATE-----\s*([\s\S]*?)-----END CERTIFICATE-----',
          ).firstMatch(pem);
          if (match != null) {
            final fingerprint = sha256
                .convert(base64.decode(match[1]!.replaceAll(RegExp(r'\s'), '')))
                .toString();
            client.badCertificateCallback = (certificate, host, port) =>
                host == uri.host &&
                port == uri.port &&
                sha256.convert(certificate.der).toString() == fingerprint &&
                DateTime.now().isAfter(certificate.startValidity) &&
                DateTime.now().isBefore(certificate.endValidity);
          }
        }
      } catch (_) {
        // Missing discovery trust never disables certificate validation.
      }
    }
    return client;
  }

  void _addAuthorization(HttpClientRequest request) {
    final token = _token;
    if (token != null && token.isNotEmpty) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }
  }
}
