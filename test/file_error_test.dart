import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:host_deck/server/features/files/file_error.dart';

void main() {
  group('describeFileOperationError', () {
    test('SftpStatusError code 3 返回权限不足提示', () {
      final error = SftpStatusError(3, 'Permission denied');

      final message = describeFileOperationError(error);

      expect(message, contains('权限不足'));
      expect(message, isNot(contains('SftpStatusError')));
    });

    test('SftpStatusError code 2 返回不存在提示', () {
      final error = SftpStatusError(2, 'No such file');

      final message = describeFileOperationError(error);

      expect(message, contains('不存在'));
      expect(message, isNot(contains('SftpStatusError')));
    });

    test('其他 SftpStatusError code 返回通用失败并保留原始信息', () {
      final error = SftpStatusError(4, 'Failure');

      final message = describeFileOperationError(error);

      expect(message, contains('SFTP 操作失败'));
      expect(message, contains('code 4'));
      expect(message, contains('Failure'));
    });

    test('非 SftpStatusError 回退到原始错误信息', () {
      final error = StateError('Session not found');

      final message = describeFileOperationError(error);

      expect(message, contains('Session not found'));
    });

    test('普通异常回退到 toString', () {
      final error = Exception('boom');

      expect(describeFileOperationError(error), error.toString());
    });

    test('SftpError 返回文件操作失败前缀', () {
      final error = SftpError('unexpected');

      expect(describeFileOperationError(error), contains('unexpected'));
    });
  });
}
