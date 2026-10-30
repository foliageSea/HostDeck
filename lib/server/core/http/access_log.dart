import 'package:shelf/shelf.dart';

String formatAccessLog(Request request, int statusCode, Duration elapsed) {
  final path = request.url.path.isEmpty ? '/' : '/${request.url.path}';
  final query = request.url.hasQuery ? ' | ${request.url.query}' : '';
  return '${request.method} $path $statusCode ${elapsed.inMilliseconds}ms$query';
}
