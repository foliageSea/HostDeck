import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:pointycastle/export.dart';

import 'package:host_deck/utils/runtime_paths.dart';

class AiAgentSecretStore {
  static const _version = 'v1';
  static final _associatedData = Uint8List.fromList(
    utf8.encode('hostdeck.ai-agent.api-key.v1'),
  );

  final String? _dataDir;
  Uint8List? _key;

  AiAgentSecretStore({String? dataDir}) : _dataDir = dataDir;

  Future<void> init() async {
    final directory = await RuntimePaths.resolveDataDirectory(
      overridePath: _dataDir,
    );
    final keyFile = File(p.join(directory.path, 'ai_agent.key'));
    if (await keyFile.exists()) {
      await _restrictPermissions(keyFile);
      final bytes = await keyFile.readAsBytes();
      if (bytes.length != 32) {
        throw StateError('AI agent secret key is invalid.');
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
      throw FormatException('Unsupported AI agent secret format.');
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

  Uint8List _requireKey() {
    final key = _key;
    if (key == null) throw StateError('AI agent secret store is not ready.');
    return key;
  }

  Uint8List _randomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }

  Future<void> _restrictPermissions(File keyFile) async {
    if (Platform.isWindows) return;
    final result = await Process.run('chmod', ['600', keyFile.path]);
    if (result.exitCode != 0) {
      throw StateError('Unable to secure the AI agent secret key.');
    }
  }
}
