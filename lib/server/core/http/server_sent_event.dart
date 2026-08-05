import 'dart:convert';

List<int> encodeServerSentEvent(String event, Object? data) {
  return utf8.encode('event: $event\ndata: ${jsonEncode(data)}\n\n');
}
