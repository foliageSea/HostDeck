import 'package:flutter_test/flutter_test.dart';
import 'package:host_deck/server/app/server_handlers.dart';
import 'package:logging/logging.dart';
import 'package:shelf/shelf.dart';

void main() {
  test('formats access logs with path, duration, and query parameters', () {
    final request = Request(
      'GET',
      Uri.parse(
        'http://localhost/api/docker/images?connectionId=1&page=1&pageSize=100',
      ),
    );

    expect(
      formatAccessLog(request, 200, const Duration(milliseconds: 152)),
      'GET /api/docker/images 200 152ms '
      '| connectionId=1&page=1&pageSize=100',
    );
  });

  test('formats the root path without a query string', () {
    final request = Request('GET', Uri.parse('http://localhost/'));

    expect(
      formatAccessLog(request, 404, const Duration(milliseconds: 3)),
      'GET / 404 3ms',
    );
  });

  test(
    'allows WebSocket hijack exceptions to reach the Shelf adapter',
    () async {
      final middleware = accessLogMiddleware(Logger('access-log-test'));
      final handler = middleware((_) => throw const HijackException());

      await expectLater(
        handler(Request('GET', Uri.parse('http://localhost/api/ws'))),
        throwsA(isA<HijackException>()),
      );
    },
  );
}
