import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:host_deck/server/core/http/result.dart';

void main() {
  test(
    'Result.fail uses the supplied HTTP status and preserves JSON envelope',
    () async {
      final response = Result.fail(429, 'Too many requests');

      expect(response.statusCode, 429);
      expect(response.headers['content-type'], 'application/json');
      expect(jsonDecode(await response.readAsString()), {
        'code': 429,
        'message': 'Too many requests',
        'data': null,
      });
    },
  );
}
