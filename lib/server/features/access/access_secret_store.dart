import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:pointycastle/export.dart';

import 'package:host_deck/utils/runtime_paths.dart';

class AccessSecretStore {
  static const _version = 'v1';
  static final _associatedData = Uint8List.fromList(
    utf8.encode('hostdeck.access.totp.v1'),
  );

  final String? _dataDir;
  Uint8List? _key;
  String? _totpSecret;
  List<String> _recoveryCodeHashes = const [];

  AccessSecretStore({String? dataDir}) : _dataDir = dataDir;

  String? get totpSecret => _totpSecret;

  int get recoveryCodesRemaining => _recoveryCodeHashes.length;

  Future<void> init() async {
    final directory = await RuntimePaths.resolveDataDirectory(
      overridePath: _dataDir,
    );
    await directory.create(recursive: true);

    final keyFile = File(p.join(directory.path, 'access_auth.key'));
    await _loadOrCreateKey(keyFile);

    final stateFile = File(p.join(directory.path, 'access_auth.json'));
    if (!await stateFile.exists()) return;
    await _restrictPermissions(stateFile);

    final raw = await stateFile.readAsString();
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw StateError('Access authentication state is invalid.');
    }

    final encryptedSecret = decoded['totpSecret'];
    if (encryptedSecret is String && encryptedSecret.isNotEmpty) {
      _totpSecret = decrypt(encryptedSecret);
    }

    final hashes = decoded['recoveryCodeHashes'];
    if (hashes is List) {
      _recoveryCodeHashes = hashes
          .whereType<String>()
          .where((value) => value.isNotEmpty)
          .toList(growable: true);
    }
  }

  Future<void> saveTotp({
    required String secret,
    required List<String> recoveryCodeHashes,
  }) async {
    _totpSecret = secret;
    _recoveryCodeHashes = List<String>.from(recoveryCodeHashes);
    await _saveState();
  }

  Future<void> clearTotp() async {
    _totpSecret = null;
    _recoveryCodeHashes = const [];
    await _saveState();
  }

  Future<bool> consumeRecoveryCodeHash(String hash) async {
    final index = _recoveryCodeHashes.indexOf(hash);
    if (index < 0) return false;
    _recoveryCodeHashes = List<String>.from(_recoveryCodeHashes)
      ..removeAt(index);
    await _saveState();
    return true;
  }

  String encrypt(String plaintext) {
    final key = _requireKey();
    final nonce = _randomBytes(12);
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        true,
        AEADParameters(KeyParameter(key), 128, nonce, _associatedData),
      );
    final ciphertext = cipher.process(
      Uint8List.fromList(utf8.encode(plaintext)),
    );
    return '$_version.${base64Url.encode(nonce)}.${base64Url.encode(ciphertext)}';
  }

  String decrypt(String encoded) {
    final parts = encoded.split('.');
    if (parts.length != 3 || parts.first != _version) {
      throw FormatException('Unsupported access secret format.');
    }

    final nonce = base64Url.decode(parts[1]);
    final ciphertext = base64Url.decode(parts[2]);
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        false,
        AEADParameters(
          KeyParameter(_requireKey()),
          128,
          nonce,
          _associatedData,
        ),
      );
    return utf8.decode(cipher.process(ciphertext));
  }

  List<String> get recoveryCodeHashes => List.unmodifiable(_recoveryCodeHashes);

  Future<void> _saveState() async {
    final directory = await RuntimePaths.resolveDataDirectory(
      overridePath: _dataDir,
    );
    await directory.create(recursive: true);
    final stateFile = File(p.join(directory.path, 'access_auth.json'));
    await stateFile.writeAsString(
      jsonEncode({
        'version': 1,
        'totpSecret': _totpSecret == null ? null : encrypt(_totpSecret!),
        'recoveryCodeHashes': _recoveryCodeHashes,
      }),
      flush: true,
    );
    await _restrictPermissions(stateFile);
  }

  Future<void> _loadOrCreateKey(File keyFile) async {
    if (await keyFile.exists()) {
      await _restrictPermissions(keyFile);
      final bytes = await keyFile.readAsBytes();
      if (bytes.length != 32) {
        throw StateError('Access authentication key is invalid.');
      }
      _key = Uint8List.fromList(bytes);
      return;
    }

    final key = _randomBytes(32);
    await keyFile.create(exclusive: true);
    await _restrictPermissions(keyFile);
    await keyFile.writeAsBytes(key, flush: true);
    _key = key;
  }

  Uint8List _requireKey() {
    final key = _key;
    if (key == null) {
      throw StateError('Access authentication secret store is not ready.');
    }
    return key;
  }

  Uint8List _randomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }

  Future<void> _restrictPermissions(File file) async {
    if (Platform.isWindows) return;
    final result = await Process.run('chmod', ['600', file.path]);
    if (result.exitCode != 0) {
      throw StateError('Unable to secure the access authentication file.');
    }
  }
}
