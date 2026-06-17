import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// AES-256-CBC encryption helper.
///
/// Used to encrypt sensitive fields such as SSH passwords and private keys.
/// Ciphertext format: `base64(iv):base64(ciphertext)`.
///
/// The built-in key provides basic protection against direct database reads.
/// For stronger protection, derive this key from machine-specific material.
class CryptoHelper {
  // AES-256 requires a 32-byte key.
  static final Uint8List _key = Uint8List.fromList(
    base64.decode('aG9zdERlY2tTZWNyZXRLZXkyMDI0QUVTMjU2Qml0ISE='),
  );

  static final Random _random = Random.secure();

  /// Encrypts text into `base64(iv):base64(ciphertext)` format.
  /// Returns null for null or empty input.
  static String? encrypt(String? plaintext) {
    if (plaintext == null || plaintext.isEmpty) return null;

    final iv = _generateIV();
    final cipher = _buildCipher(true, iv);

    final output = cipher.process(_toBytes(plaintext));

    return '${base64.encode(iv)}:${base64.encode(output)}';
  }

  /// Decrypts `base64(iv):base64(ciphertext)` text.
  /// Returns the original value for legacy plaintext or invalid input.
  static String? decrypt(String? ciphertext) {
    if (ciphertext == null || ciphertext.isEmpty) return null;

    final parts = ciphertext.split(':');
    // Non-matching data is legacy plaintext.
    if (parts.length != 2) return ciphertext;

    try {
      final iv = base64.decode(parts[0]);
      final encrypted = base64.decode(parts[1]);

      final cipher = _buildCipher(false, Uint8List.fromList(iv));
      final decrypted = cipher.process(Uint8List.fromList(encrypted));
      return utf8.decode(decrypted);
    } catch (_) {
      // Invalid data is treated as legacy plaintext.
      return ciphertext;
    }
  }

  /// Returns true when the value can be decrypted by this helper.
  static bool isEncrypted(String? value) {
    if (value == null || value.isEmpty) return true;

    final parts = value.split(':');
    if (parts.length != 2) return false;

    try {
      final iv = base64.decode(parts[0]);
      final encrypted = base64.decode(parts[1]);
      if (iv.length != 16 || encrypted.isEmpty || encrypted.length % 16 != 0) {
        return false;
      }

      final cipher = _buildCipher(false, Uint8List.fromList(iv));
      final decrypted = cipher.process(Uint8List.fromList(encrypted));
      utf8.decode(decrypted);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Generates a random 16-byte IV.
  static Uint8List _generateIV() {
    final iv = Uint8List(16);
    for (var i = 0; i < 16; i++) {
      iv[i] = _random.nextInt(256);
    }
    return iv;
  }

  /// Creates an AES-256-CBC cipher.
  static PaddedBlockCipher _buildCipher(bool forEncryption, Uint8List iv) {
    final params = PaddedBlockCipherParameters(
      ParametersWithIV(KeyParameter(_key), iv),
      null,
    );
    final cipher = PaddedBlockCipher('AES/CBC/PKCS7');
    cipher.init(forEncryption, params);
    return cipher;
  }

  /// Converts text to UTF-8 bytes.
  static Uint8List _toBytes(String text) =>
      Uint8List.fromList(utf8.encode(text));
}
