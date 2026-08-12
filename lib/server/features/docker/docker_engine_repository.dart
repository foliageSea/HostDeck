import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:host_deck/server/core/ssh/ssh_session.dart';
import 'package:host_deck/server/features/docker/docker_socket_tunnel_service.dart';

typedef DockerEngineEndpointProvider = Future<Uri> Function(SshSession session);
typedef DockerEngineHttpClientFactory = HttpClient Function();

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
  final Uint8List bodyBytes;

  const DockerEngineResponse({
    required this.statusCode,
    required this.bodyBytes,
  });

  String get body => utf8.decode(bodyBytes);
}

enum DockerEngineStreamSource { body, stderr }

class DockerEngineStreamEvent {
  final DockerEngineStreamSource? source;
  final String text;
  final int? statusCode;
  final int? exitCode;
  final bool completed;

  const DockerEngineStreamEvent.output(this.source, this.text)
    : statusCode = null,
      exitCode = null,
      completed = false;

  const DockerEngineStreamEvent.completed(this.statusCode, this.exitCode)
    : source = null,
      text = '',
      completed = true;
}

class DockerEngineRepository {
  final DockerEngineEndpointProvider _endpointProvider;
  final HttpClient _httpClient;

  DockerEngineRepository({
    DockerSocketTunnelService? tunnelService,
    DockerEngineEndpointProvider? endpointProvider,
    DockerEngineHttpClientFactory? httpClientFactory,
  }) : _endpointProvider =
           endpointProvider ??
           (tunnelService ?? DockerSocketTunnelService()).endpoint,
       _httpClient = (httpClientFactory ?? HttpClient.new)() {
    _httpClient.autoUncompress = false;
    _httpClient.maxConnectionsPerHost = 4;
  }

  void close() => _httpClient.close(force: true);

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

  Future<Uint8List> requestBytes(
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
    return response.bodyBytes;
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
    return response.trim().isEmpty ? null : jsonDecode(response);
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
    final response = await _send(
      session,
      method: method,
      path: path,
      queryParameters: queryParameters,
      body: body,
      headers: headers,
    );
    final bytes = await _readBytes(response);
    _throwForStatus(response.statusCode, bytes);
    return DockerEngineResponse(
      statusCode: response.statusCode,
      bodyBytes: bytes,
    );
  }

  Future<Stream<Uint8List>> requestByteStream(
    SshSession session, {
    required String method,
    required String path,
    Map<String, String>? queryParameters,
    Object? body,
    Map<String, String>? headers,
  }) async {
    final response = await _send(
      session,
      method: method,
      path: path,
      queryParameters: queryParameters,
      body: body,
      headers: headers,
    );
    if (response.statusCode >= 400) {
      final bytes = await _readBytes(response);
      _throwForStatus(response.statusCode, bytes);
    }
    return response.map(
      (chunk) => chunk is Uint8List ? chunk : Uint8List.fromList(chunk),
    );
  }

  Stream<DockerEngineStreamEvent> requestStream(
    SshSession session, {
    required String method,
    required String path,
    Map<String, String>? queryParameters,
    Object? body,
    Map<String, String>? headers,
    Duration timeout = const Duration(hours: 1),
  }) async* {
    final response = await _send(
      session,
      method: method,
      path: path,
      queryParameters: queryParameters,
      body: body,
      headers: headers,
    );
    if (response.statusCode >= 400) {
      final bytes = await _readBytes(response);
      _throwForStatus(response.statusCode, bytes);
    }

    await for (final text in const Utf8Decoder(
      allowMalformed: true,
    ).bind(response).timeout(timeout)) {
      yield DockerEngineStreamEvent.output(DockerEngineStreamSource.body, text);
    }
    yield DockerEngineStreamEvent.completed(response.statusCode, 0);
  }

  Future<HttpClientResponse> _send(
    SshSession session, {
    required String method,
    required String path,
    Map<String, String>? queryParameters,
    Object? body,
    Map<String, String>? headers,
  }) async {
    final endpoint = await _endpointProvider(session);
    final uri = endpoint
        .resolveUri(Uri.parse(path))
        .replace(
          queryParameters: queryParameters == null || queryParameters.isEmpty
              ? null
              : queryParameters,
        );
    final request = await _httpClient.openUrl(method.toUpperCase(), uri);
    headers?.forEach(request.headers.set);

    if (body != null) {
      if (!_hasHeader(headers, HttpHeaders.contentTypeHeader)) {
        request.headers.contentType = body is Stream<List<int>>
            ? ContentType.binary
            : ContentType.json;
      }
      if (body is Stream<List<int>>) {
        await request.addStream(body);
      } else if (body is List<int>) {
        request.add(body);
      } else if (body is String) {
        request.add(utf8.encode(body));
      } else {
        request.add(utf8.encode(jsonEncode(body)));
      }
    }
    return request.close();
  }

  bool _hasHeader(Map<String, String>? headers, String name) {
    return headers?.keys.any((key) => key.toLowerCase() == name) ?? false;
  }

  Future<Uint8List> _readBytes(Stream<List<int>> stream) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in stream) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  void _throwForStatus(int statusCode, Uint8List bodyBytes) {
    if (statusCode < 400) {
      return;
    }
    final body = utf8.decode(bodyBytes, allowMalformed: true).trim();
    var message = body.isEmpty
        ? 'Docker Engine API returned an empty error response'
        : body;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['message'] != null) {
        message = decoded['message'].toString();
      }
    } catch (_) {
      // Preserve a non-JSON Engine error response verbatim.
    }
    throw DockerEngineHttpException(statusCode, message);
  }
}
