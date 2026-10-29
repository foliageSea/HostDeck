import 'package:dartssh2/dartssh2.dart';

/// SFTP 状态码，参考 RFC 913 / SFTP v3 协议定义。
class SftpErrorCode {
  static const int noSuchFile = 2;
  static const int permissionDenied = 3;
  static const int noConnection = 7;
  static const int opUnsupported = 8;

  const SftpErrorCode._();
}

/// 把文件操作抛出的异常转成可以直接展示给用户的中文消息。
///
/// - [SftpStatusError] code 3（权限不足）-> 提示检查权限；
/// - [SftpStatusError] code 2（不存在）-> 提示文件或目录不存在；
/// - 其他 SFTP 状态码 -> 通用失败描述，并保留 code 与远端原始信息；
/// - 非 [SftpStatusError] -> 回退到 [Object.toString]，保证原始信息不丢失。
String describeFileOperationError(Object error) {
  if (error is SftpStatusError) {
    return describeSftpStatusError(error);
  }

  if (error is SftpError) {
    return '文件操作失败：${error.message}';
  }

  return error.toString();
}

/// 针对 [SftpStatusError] 的友好中文描述，拆出来方便直接单测。
String describeSftpStatusError(SftpStatusError error) {
  return switch (error.code) {
    SftpErrorCode.permissionDenied => '权限不足，无法访问该目录或文件，请联系管理员检查 SSH 用户权限。',
    SftpErrorCode.noSuchFile => '文件或目录不存在，可能已被移动或删除。',
    _ => 'SFTP 操作失败（code ${error.code}）：${error.message}',
  };
}
