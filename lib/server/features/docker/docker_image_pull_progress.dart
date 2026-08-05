import 'dart:convert';

Map<String, dynamic> decodeDockerImagePullProgress(String line) {
  final decoded = jsonDecode(line);
  if (decoded is! Map) {
    throw const FormatException('Invalid Docker image pull progress');
  }
  return Map<String, dynamic>.from(decoded);
}

String? dockerImagePullError(Map<String, dynamic> data) {
  final detail = data['errorDetail'];
  if (detail is Map &&
      detail['message']?.toString().trim().isNotEmpty == true) {
    return detail['message'].toString().trim();
  }
  final error = data['error']?.toString().trim() ?? '';
  return error.isEmpty ? null : error;
}
