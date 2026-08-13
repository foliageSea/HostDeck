import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:host_deck/server/core/http/server_sent_event.dart';

void main() {
  test('encodes an SSE event with JSON data', () {
    final encoded = utf8.decode(
      encodeServerSentEvent('stdout', {'text': 'line 1\nline 2'}),
    );

    expect(encoded, 'event: stdout\ndata: {"text":"line 1\\nline 2"}\n\n');
  });

  test('encodes optional id and retry fields', () {
    final encoded = utf8.decode(
      encodeServerSentEvent('log', {'message': 'ready'}, id: 42, retry: 3000),
    );

    expect(
      encoded,
      'id: 42\nevent: log\nretry: 3000\ndata: {"message":"ready"}\n\n',
    );
  });

  test('rejects a negative retry interval', () {
    expect(
      () => encodeServerSentEvent('log', const {}, retry: -1),
      throwsArgumentError,
    );
  });
}
