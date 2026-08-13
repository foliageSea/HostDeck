import 'dart:convert';

List<int> encodeServerSentEvent(
  String event,
  Object? data, {
  Object? id,
  int? retry,
}) {
  final buffer = StringBuffer();
  if (id != null) {
    buffer.writeln('id: ${_singleLine(id.toString())}');
  }
  buffer.writeln('event: ${_singleLine(event)}');
  if (retry != null) {
    if (retry < 0) {
      throw ArgumentError.value(retry, 'retry', 'must not be negative');
    }
    buffer.writeln('retry: $retry');
  }
  buffer
    ..writeln('data: ${jsonEncode(data)}')
    ..writeln();
  return utf8.encode(buffer.toString());
}

String _singleLine(String value) => value.replaceAll(RegExp(r'[\r\n]'), '');
