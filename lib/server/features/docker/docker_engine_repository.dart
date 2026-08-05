import 'dart:convert';
import 'dart:typed_data';

import 'package:host_deck/server/core/ssh/ssh_repository.dart';
import 'package:host_deck/server/core/ssh/ssh_session.dart';

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
  static const _statusMarker = '__HOST_DECK_HTTP_STATUS__';

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
    final command = _buildRequestCommand(
      method: method,
      path: path,
      queryParameters: queryParameters,
      body: body,
      headers: headers,
      mergeStderr: true,
    );
    final output = await _sshRepository.execBytes(session, command);
    final markerBytes = Uint8List.fromList(utf8.encode('\n$_statusMarker:'));
    final markerIndex = _lastIndexOfBytes(output, markerBytes);

    if (markerIndex < 0) {
      final outputText = utf8.decode(output, allowMalformed: true);
      final message = outputText.trim().isEmpty
          ? 'Docker Engine API request failed without a response marker'
          : outputText.trim();
      throw Exception(message);
    }

    final bodyBytes = Uint8List.sublistView(output, 0, markerIndex);
    final statusStart = markerIndex + markerBytes.length;
    final statusBytes = Uint8List.sublistView(output, statusStart);
    final statusText = utf8.decode(statusBytes, allowMalformed: true).trim();
    final statusCode = int.tryParse(statusText);
    if (statusCode == null) {
      throw Exception('Invalid Docker Engine API status code: $statusText');
    }

    if (statusCode >= 400) {
      final bodyText = utf8.decode(bodyBytes, allowMalformed: true);
      throw DockerEngineHttpException(
        statusCode,
        _extractErrorMessage(bodyText),
      );
    }

    return DockerEngineResponse(statusCode: statusCode, bodyBytes: bodyBytes);
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
    final command = _buildRequestCommand(
      method: method,
      path: path,
      queryParameters: queryParameters,
      body: body,
      headers: headers,
      mergeStderr: false,
    );
    const retainedTailLength = 128;
    final stderr = StringBuffer();
    var pending = '';
    int? exitCode;

    await for (final event in _sshRepository.execStream(
      session,
      command,
      timeout: timeout,
    )) {
      if (event.completed) {
        exitCode = event.exitCode;
        continue;
      }

      if (event.source == SshExecStreamSource.stderr) {
        stderr.write(event.text);
        yield DockerEngineStreamEvent.output(
          DockerEngineStreamSource.stderr,
          event.text,
        );
        continue;
      }

      pending += event.text;
      if (pending.length > retainedTailLength) {
        final emitLength = pending.length - retainedTailLength;
        yield DockerEngineStreamEvent.output(
          DockerEngineStreamSource.body,
          pending.substring(0, emitLength),
        );
        pending = pending.substring(emitLength);
      }
    }

    final marker = '\n$_statusMarker:';
    final markerIndex = pending.lastIndexOf(marker);
    if (markerIndex < 0) {
      final message = stderr.toString().trim();
      throw Exception(
        message.isEmpty
            ? 'Docker Engine API request failed without a response marker'
            : message,
      );
    }

    final remainingBody = pending.substring(0, markerIndex);
    if (remainingBody.isNotEmpty) {
      yield DockerEngineStreamEvent.output(
        DockerEngineStreamSource.body,
        remainingBody,
      );
    }
    final statusText = pending.substring(markerIndex + marker.length).trim();
    final statusCode = int.tryParse(statusText);
    if (statusCode == null || statusCode == 0) {
      throw Exception('Invalid Docker Engine API status code: $statusText');
    }

    yield DockerEngineStreamEvent.completed(statusCode, exitCode);
  }

  String _buildRequestCommand({
    required String method,
    required String path,
    Map<String, String>? queryParameters,
    Object? body,
    Map<String, String>? headers,
    required bool mergeStderr,
  }) {
    final normalizedHeaders = <String, String>{...?headers};
    final args = <String>[
      'curl',
      '--silent',
      '--show-error',
      '--no-buffer',
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

    final command = '${args.join(' ')}${mergeStderr ? ' 2>&1' : ''}';
    return 'sh -lc ${_shellQuote(command)}';
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

  int _lastIndexOfBytes(Uint8List bytes, Uint8List pattern) {
    if (pattern.isEmpty || bytes.length < pattern.length) {
      return -1;
    }

    for (var index = bytes.length - pattern.length; index >= 0; index--) {
      var matched = true;
      for (var offset = 0; offset < pattern.length; offset++) {
        if (bytes[index + offset] != pattern[offset]) {
          matched = false;
          break;
        }
      }
      if (matched) {
        return index;
      }
    }

    return -1;
  }
}
