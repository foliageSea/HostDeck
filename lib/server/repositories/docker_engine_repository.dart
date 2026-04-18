import 'dart:convert';

import '../models/ssh_session.dart';
import 'ssh_repository.dart';

class DockerEngineHttpException implements Exception {
  final int statusCode;
  final String message;

  DockerEngineHttpException(this.statusCode, this.message);

  @override
  String toString() =>
      'Docker Engine API request failed ($statusCode): $message';
}

class DockerEngineResponse {
  final int statusCode;
  final String body;

  const DockerEngineResponse({required this.statusCode, required this.body});
}

class DockerEngineRepository {
  static const _statusMarker = '__SSH_TOOL_HTTP_STATUS__';

  final SshRepository _sshRepository;
  final String socketPath;

  DockerEngineRepository(
    this._sshRepository, {
    this.socketPath = '/var/run/docker.sock',
  });

  Future<bool> ping(SshSession session) async {
    try {
      final body = await requestText(session, method: 'GET', path: '/_ping');
      return body.trim() == 'OK';
    } catch (_) {
      return false;
    }
  }

  Future<String> requestText(
    SshSession session, {
    required String method,
    required String path,
    Map<String, String>? queryParameters,
    Object? body,
    Map<String, String>? headers,
  }) async {
    final response = await request(
      session,
      method: method,
      path: path,
      queryParameters: queryParameters,
      body: body,
      headers: headers,
    );
    return response.body;
  }

  Future<dynamic> requestJson(
    SshSession session, {
    required String method,
    required String path,
    Map<String, String>? queryParameters,
    Object? body,
    Map<String, String>? headers,
  }) async {
    final response = await requestText(
      session,
      method: method,
      path: path,
      queryParameters: queryParameters,
      body: body,
      headers: headers,
    );

    final trimmed = response.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    return jsonDecode(trimmed);
  }

  Future<Map<String, dynamic>> requestJsonObject(
    SshSession session, {
    required String method,
    required String path,
    Map<String, String>? queryParameters,
    Object? body,
    Map<String, String>? headers,
  }) async {
    final decoded = await requestJson(
      session,
      method: method,
      path: path,
      queryParameters: queryParameters,
      body: body,
      headers: headers,
    );

    if (decoded is Map) {
      return Map<String, dynamic>.from(decoded);
    }

    throw Exception('Docker Engine API did not return a JSON object');
  }

  Future<List<dynamic>> requestJsonList(
    SshSession session, {
    required String method,
    required String path,
    Map<String, String>? queryParameters,
    Object? body,
    Map<String, String>? headers,
  }) async {
    final decoded = await requestJson(
      session,
      method: method,
      path: path,
      queryParameters: queryParameters,
      body: body,
      headers: headers,
    );

    if (decoded is List) {
      return decoded;
    }

    throw Exception('Docker Engine API did not return a JSON array');
  }

  Future<DockerEngineResponse> request(
    SshSession session, {
    required String method,
    required String path,
    Map<String, String>? queryParameters,
    Object? body,
    Map<String, String>? headers,
  }) async {
    final normalizedHeaders = <String, String>{...?headers};
    final args = <String>[
      'curl',
      '--silent',
      '--show-error',
      '--globoff',
      '--unix-socket ${_shellQuote(socketPath)}',
      '-X ${_shellQuote(method.toUpperCase())}',
      '--write-out ${_shellQuote('\n$_statusMarker:%{http_code}')}',
    ];

    if (body != null && !normalizedHeaders.containsKey('Content-Type')) {
      normalizedHeaders['Content-Type'] = 'application/json';
    }

    normalizedHeaders.forEach((key, value) {
      args.add('-H ${_shellQuote('$key: $value')}');
    });

    if (body != null) {
      final encodedBody = body is String ? body : jsonEncode(body);
      args.add('--data-binary ${_shellQuote(encodedBody)}');
    }

    args.add(_shellQuote(_buildUrl(path, queryParameters)));

    final command = 'sh -lc ${_shellQuote('${args.join(' ')} 2>&1')}';
    final output = await _sshRepository.exec(session, command);
    final marker = '\n$_statusMarker:';
    final markerIndex = output.lastIndexOf(marker);

    if (markerIndex < 0) {
      final message = output.trim().isEmpty
          ? 'Docker Engine API request failed without a response marker'
          : output.trim();
      throw Exception(message);
    }

    final bodyText = output.substring(0, markerIndex);
    final statusText = output.substring(markerIndex + marker.length).trim();
    final statusCode = int.tryParse(statusText);
    if (statusCode == null) {
      throw Exception('Invalid Docker Engine API status code: $statusText');
    }

    if (statusCode >= 400) {
      throw DockerEngineHttpException(
        statusCode,
        _extractErrorMessage(bodyText),
      );
    }

    return DockerEngineResponse(statusCode: statusCode, body: bodyText);
  }

  String _buildUrl(String path, Map<String, String>? queryParameters) {
    final uri = Uri(
      scheme: 'http',
      host: 'localhost',
      path: path,
      queryParameters: queryParameters == null || queryParameters.isEmpty
          ? null
          : queryParameters,
    );
    return uri.toString();
  }

  String _extractErrorMessage(String body) {
    final trimmed = body.trim();
    if (trimmed.isEmpty) {
      return 'Docker Engine API returned an empty error response';
    }

    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map && decoded['message'] != null) {
        return decoded['message'].toString();
      }
    } catch (_) {
      // Ignore JSON decode failure and fall back to the raw response body.
    }

    return trimmed;
  }

  String _shellQuote(String value) {
    return "'${value.replaceAll("'", "'\\''")}'";
  }
}
