import 'package:flutter_test/flutter_test.dart';
import '../bin/server.dart' as server;
import 'package:logging/logging.dart';

void main() {
  test('aligns logger names to a fixed width', () {
    final record = LogRecord(Level.INFO, 'Server started', 'AppSettings');
    final line = server.formatLogRecord(record);

    expect(
      line,
      matches(RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3} ')),
    );
    expect(line, contains(' INFO    '));
    expect(line, endsWith('${'AppSettings'.padRight(24)} | Server started'));
  });

  test('keeps logger names longer than the column width intact', () {
    final record = LogRecord(
      Level.WARNING,
      'Slow response',
      'LongerThanTwentyFourCharacterLogger',
    );
    final line = server.formatLogRecord(record);

    expect(
      line,
      endsWith('LongerThanTwentyFourCharacterLogger | Slow response'),
    );
  });
}
