import 'package:flutter_test/flutter_test.dart';
import 'package:host_deck/utils/crypto_helper.dart';

void main() {
  group('CryptoHelper', () {
    test('加密后解密应还原原始字符串', () {
      const original = 'MySecretP@ssw0rd!';
      final encrypted = CryptoHelper.encrypt(original);
      expect(encrypted, isNotNull);
      expect(encrypted, isNot(equals(original)));
      final decrypted = CryptoHelper.decrypt(encrypted);
      expect(decrypted, equals(original));
    });

    test('每次加密同一字符串应产生不同密文（随机 IV）', () {
      const original = 'same-password';
      final enc1 = CryptoHelper.encrypt(original);
      final enc2 = CryptoHelper.encrypt(original);
      expect(enc1, isNot(equals(enc2)));
      // 但解密结果应相同
      expect(CryptoHelper.decrypt(enc1), equals(original));
      expect(CryptoHelper.decrypt(enc2), equals(original));
    });

    test('null 输入返回 null', () {
      expect(CryptoHelper.encrypt(null), isNull);
      expect(CryptoHelper.decrypt(null), isNull);
    });

    test('空字符串返回 null', () {
      expect(CryptoHelper.encrypt(''), isNull);
      expect(CryptoHelper.decrypt(''), isNull);
    });

    test('非加密格式字符串（旧明文数据）解密时直接透传', () {
      const plaintext = 'old-plain-password';
      final result = CryptoHelper.decrypt(plaintext);
      expect(result, equals(plaintext));
      expect(CryptoHelper.isEncrypted(plaintext), isFalse);
    });

    test('包含冒号的旧明文数据不应被识别为加密值', () {
      const plaintext = 'old:plain:password';
      expect(CryptoHelper.decrypt(plaintext), equals(plaintext));
      expect(CryptoHelper.isEncrypted(plaintext), isFalse);
    });

    test('加密结果应被识别为加密值', () {
      final encrypted = CryptoHelper.encrypt('secret');
      expect(CryptoHelper.isEncrypted(encrypted), isTrue);
    });

    test('能正确处理含特殊字符的密码', () {
      const special = r'P@$$w0rd!#%^&*()_+-=[]{}|;:",./<>?~`';
      final enc = CryptoHelper.encrypt(special);
      expect(CryptoHelper.decrypt(enc), equals(special));
    });

    test('能正确处理长字符串（私钥场景）', () {
      final longKey =
          '-----BEGIN RSA PRIVATE KEY-----\n'
          '${'A' * 800}\n'
          '-----END RSA PRIVATE KEY-----';
      final enc = CryptoHelper.encrypt(longKey);
      expect(CryptoHelper.decrypt(enc), equals(longKey));
    });

    test('密文格式应为 base64:base64', () {
      final enc = CryptoHelper.encrypt('test');
      expect(enc, isNotNull);
      final parts = enc!.split(':');
      expect(parts.length, equals(2));
      // 验证两部分都是有效 base64
      expect(() => Uri.parse('data:;base64,${parts[0]}'), returnsNormally);
      expect(() => Uri.parse('data:;base64,${parts[1]}'), returnsNormally);
    });
  });
}
