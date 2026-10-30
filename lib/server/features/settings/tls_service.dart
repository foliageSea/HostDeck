import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart';
import 'package:path/path.dart' as p;
import 'package:pointycastle/asn1.dart';

import 'package:host_deck/utils/runtime_paths.dart';

class TlsValidationException implements Exception {
  final String message;
  const TlsValidationException(this.message);
  @override
  String toString() => message;
}

class TlsService {
  final String? dataDir;
  final bool? enabledOverride;
  final String? certificatePath;
  final String? privateKeyPath;
  late Directory _directory;
  Map<String, dynamic> _saved = {'enabled': false, 'source': 'selfSigned'};
  Map<String, dynamic> _active = {};
  String? activeCertificate;
  SecurityContext? securityContext;
  bool _saving = false;

  TlsService({
    this.dataDir,
    this.enabledOverride,
    this.certificatePath,
    this.privateKeyPath,
  });

  bool get enabled => _active['enabled'] == true;
  String get scheme => enabled ? 'https' : 'http';
  bool get managedExternally =>
      enabledOverride != null || certificatePath != null;

  Future<void> init() async {
    _directory = await RuntimePaths.resolveDataDirectory(overridePath: dataDir);
    await _directory.create(recursive: true);
    final file = File(p.join(_directory.path, 'tls.json'));
    if (await file.exists()) {
      try {
        _saved = _validateConfig(jsonDecode(await file.readAsString()));
      } catch (_) {
        // The explicit recovery override must work even with a damaged config.
        if (enabledOverride != false) {
          throw const TlsValidationException('TLS 配置损坏，请使用 --tls false 启动后修复。');
        }
      }
    }
    if (enabledOverride != false &&
        (certificatePath == null) != (privateKeyPath == null)) {
      throw const TlsValidationException('必须同时指定 TLS 证书和私钥路径。');
    }
    _active = Map.of(_saved);
    if (enabledOverride != null) _active['enabled'] = enabledOverride;
    if (certificatePath != null && enabledOverride != false) {
      _active['enabled'] = true;
      _active['source'] = 'imported';
      try {
        final cert = await File(certificatePath!).readAsString();
        final key = await File(privateKeyPath!).readAsString();
        securityContext = await validatePair(cert, key);
        activeCertificate = cert;
        _active['certificate'] = certificateInfo(cert);
      } catch (_) {
        throw const TlsValidationException('无法加载指定的 TLS 证书或私钥。');
      }
    } else if (enabled) {
      if (_active['revision'] == null) {
        if (_active['source'] != 'selfSigned') {
          throw const TlsValidationException('请先导入 TLS 证书和私钥。');
        }
        await save({'enabled': true, 'source': 'selfSigned'});
        _active = Map.of(_saved);
      }
      final pair = await _readPair(_active);
      securityContext = await validatePair(pair.$1, pair.$2);
      activeCertificate = pair.$1;
      _active['certificate'] = certificateInfo(pair.$1);
    }
  }

  Map<String, dynamic> state() => {
    'saved': _publicConfig(_saved),
    'active': _publicConfig(_active),
    'managedExternally': managedExternally,
    'restartRequired':
        _saved['enabled'] != _active['enabled'] ||
        (enabled &&
            (_saved['revision'] != _active['revision'] ||
                _saved['certificate']?['fingerprint256'] !=
                    _active['certificate']?['fingerprint256'])),
  };

  Map<String, dynamic> _publicConfig(Map<String, dynamic> config) => {
    'enabled': config['enabled'] == true,
    'source': config['source'] ?? 'selfSigned',
    'hosts': config['hosts'] ?? const ['localhost', '127.0.0.1', '::1'],
    'certificate': config['certificate'],
  };

  Future<Map<String, dynamic>> save(Map<String, dynamic> payload) async {
    if (_saving) throw const TlsValidationException('TLS 配置正在保存，请稍后重试。');
    _saving = true;
    try {
      if (payload['enabled'] is! bool ||
          !['selfSigned', 'imported'].contains(payload['source'])) {
        throw const TlsValidationException('TLS 开关或证书来源无效。');
      }
      final source = payload['source'] as String;
      final hosts = normalizeHosts(payload['hosts'] ?? _saved['hosts']);
      final next = Map<String, dynamic>.of(_saved)
        ..['enabled'] = payload['enabled']
        ..['source'] = source;
      final certInput = payload['certificatePem'];
      final keyInput = payload['privateKeyPem'];
      final hasImport = certInput != null || keyInput != null;
      final regenerate = payload['regenerate'] == true;
      final hostsChanged = jsonEncode(hosts) != jsonEncode(_saved['hosts']);
      final needsCertificate =
          next['enabled'] == true ||
          hasImport ||
          regenerate ||
          (source == 'selfSigned' &&
              _saved['revision'] != null &&
              (hostsChanged || _saved['source'] != source));
      String? cert;
      String? key;
      if (needsCertificate) {
        if (source == 'imported' && hasImport) {
          if (certInput is! String || keyInput is! String) {
            throw const TlsValidationException('请同时上传 PEM 证书链和私钥。');
          }
          cert = certInput;
          key = keyInput;
        } else if (source == 'selfSigned' &&
            (regenerate ||
                hostsChanged ||
                _saved['source'] != source ||
                _saved['revision'] == null)) {
          final pair = await Isolate.run(() => generateCertificate(hosts));
          cert = pair.$1;
          key = pair.$2;
        } else if (_saved['source'] == source && _saved['revision'] != null) {
          final pair = await _readPair(_saved);
          cert = pair.$1;
          key = pair.$2;
        } else {
          throw const TlsValidationException('请先上传 PEM 证书链和私钥。');
        }
        await validatePair(cert, key);
        (String, String)? previous;
        if (_saved['revision'] != null) {
          try {
            previous = await _readPair(_saved);
          } catch (_) {
            // A complete replacement can repair missing certificate files.
          }
        }
        if (previous == null || previous.$1 != cert || previous.$2 != key) {
          final revision = _randomId();
          final directory = Directory(p.join(_directory.path, 'tls', revision));
          await directory.create(recursive: true);
          await _restrict(directory.path, '700');
          await _writePrivate(File(p.join(directory.path, 'key.pem')), key);
          await File(
            p.join(directory.path, 'cert.pem'),
          ).writeAsString(cert, flush: true);
          next['revision'] = revision;
        }
        next['certificate'] = certificateInfo(cert);
      } else if (_saved['source'] != source) {
        next.remove('revision');
        next.remove('certificate');
      }
      next['hosts'] = hosts;
      // Immutable certificate versions keep the running listener and its trust
      // information intact until the next successful startup.
      final file = File(p.join(_directory.path, 'tls.json'));
      final temporary = File('${file.path}.${_randomId()}.tmp');
      await _writePrivate(temporary, jsonEncode(next));
      await temporary.rename(file.path);
      _saved = next;
      return state();
    } on TlsValidationException {
      rethrow;
    } catch (_) {
      throw const TlsValidationException('保存 TLS 配置失败，请检查证书及数据目录权限。');
    } finally {
      _saving = false;
    }
  }

  Future<String?> savedCertificate() async {
    if (_saved['revision'] == null) return null;
    return (await _readPair(_saved)).$1;
  }

  Future<(String, String)> _readPair(Map<String, dynamic> config) async {
    final revision = config['revision'];
    if (revision is! String || !RegExp(r'^[a-f0-9]{32}$').hasMatch(revision)) {
      throw const TlsValidationException('TLS 证书版本无效。');
    }
    final directory = p.join(_directory.path, 'tls', revision);
    return (
      await File(p.join(directory, 'cert.pem')).readAsString(),
      await File(p.join(directory, 'key.pem')).readAsString(),
    );
  }

  static Map<String, dynamic> _validateConfig(dynamic value) {
    if (value is! Map<String, dynamic> ||
        value['enabled'] is! bool ||
        !['selfSigned', 'imported'].contains(value['source'])) {
      throw const TlsValidationException('TLS 配置无效。');
    }
    return value;
  }

  static List<String> normalizeHosts(dynamic value) {
    if (value != null && (value is! List || value.any((e) => e is! String))) {
      throw const TlsValidationException('访问域名/IP 列表无效。');
    }
    final hosts = <String>{'localhost', '127.0.0.1', '::1'};
    for (final entry in (value as List? ?? const [])) {
      final host = (entry as String).trim().toLowerCase();
      if (host.isEmpty) continue;
      final ip = InternetAddress.tryParse(host);
      if (ip == null &&
          (host.length > 253 ||
              !host
                  .split('.')
                  .every(
                    (label) => RegExp(
                      r'^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$',
                    ).hasMatch(label),
                  ))) {
        throw const TlsValidationException('请输入有效的域名或 IP，不包含协议和端口。');
      }
      hosts.add(ip?.address ?? host);
    }
    if (hosts.length > 100) {
      throw const TlsValidationException('最多配置 100 个访问域名/IP。');
    }
    return hosts.toList();
  }

  static Map<String, dynamic> certificateInfo(String pem) {
    try {
      final certificates = X509Utils.parseChainString(pem);
      if (certificates.isEmpty) throw const FormatException();
      final certificate = certificates.first;
      final tbs = certificate.tbsCertificate!;
      return {
        'subject': tbs.subject.values.whereType<String>().join(', '),
        'hosts': tbs.extensions?.subjectAlternativNames ?? const <String>[],
        'notBefore': tbs.validity.notBefore.toUtc().toIso8601String(),
        'notAfter': tbs.validity.notAfter.toUtc().toIso8601String(),
        'fingerprint256': certificate.sha256Thumbprint,
      };
    } catch (_) {
      throw const TlsValidationException('无法解析 PEM 证书链，请将服务端证书放在首位。');
    }
  }

  static Future<SecurityContext> validatePair(String cert, String key) async {
    if (cert.length > 262144 || key.length > 65536) {
      throw const TlsValidationException('证书链或私钥文件过大。');
    }
    final info = certificateInfo(cert);
    final now = DateTime.now().toUtc();
    if (now.isBefore(DateTime.parse(info['notBefore'] as String)) ||
        !now.isBefore(DateTime.parse(info['notAfter'] as String))) {
      throw const TlsValidationException('证书尚未生效或已过期。');
    }
    SecureServerSocket? listener;
    SecureSocket? client;
    SecureSocket? peer;
    try {
      final context = SecurityContext()
        ..minimumTlsProtocolVersion = TlsProtocolVersion.tls1_2
        ..useCertificateChainBytes(utf8.encode(cert))
        ..usePrivateKeyBytes(utf8.encode(key));
      listener = await SecureServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
        context,
      );
      final accepted = listener.first.timeout(const Duration(seconds: 5));
      // Observe both sides immediately so handshake failures cannot become
      // unhandled asynchronous errors.
      final connected = SecureSocket.connect(
        '127.0.0.1',
        listener.port,
        onBadCertificate: (_) => true,
        timeout: const Duration(seconds: 5),
      );
      final sockets = await Future.wait([accepted, connected]);
      peer = sockets[0];
      client = sockets[1];
      return context;
    } catch (_) {
      throw const TlsValidationException(
        '证书与私钥无法完成 TLS 握手，请检查格式、匹配关系及私钥是否未加密。',
      );
    } finally {
      client?.destroy();
      peer?.destroy();
      await listener?.close();
    }
  }

  static (String, String) generateCertificate(List<String> hosts) {
    final pair = CryptoUtils.generateRSAKeyPair();
    final privateKey = pair.privateKey as RSAPrivateKey;
    final csr = X509Utils.generateRsaCsrPem(
      {'CN': 'HostDeck'},
      privateKey,
      pair.publicKey as RSAPublicKey,
    );
    final pem = X509Utils.generateSelfSignedCertificate(
      privateKey,
      csr,
      365,
      sans: hosts,
      cA: false,
      extKeyUsage: [ExtendedKeyUsage.SERVER_AUTH],
      notBefore: DateTime.now().toUtc().subtract(const Duration(minutes: 5)),
      serialNumber: BigInt.parse(_randomId(), radix: 16).toString(),
    );
    // basic_utils encodes every SAN as DNS. Rebuild this extension so IP
    // addresses use the X.509 iPAddress tag and raw IPv4/IPv6 bytes.
    final outer =
        ASN1Parser(CryptoUtils.getBytesFromPEMString(pem)).nextObject()
            as ASN1Sequence;
    final tbs = outer.elements!.first as ASN1Sequence;
    final extensionsObject = tbs.elements!.last;
    final extensions =
        ASN1Parser(extensionsObject.valueBytes).nextObject() as ASN1Sequence;
    for (final extension in extensions.elements!.cast<ASN1Sequence>()) {
      final oid = extension.elements!.first as ASN1ObjectIdentifier;
      if (oid.objectIdentifierAsString != '2.5.29.17') continue;
      final names = ASN1Sequence(
        elements: hosts.map((host) {
          final ip = InternetAddress.tryParse(host);
          return ASN1Object(tag: ip == null ? 0x82 : 0x87)
            ..valueBytes =
                ip?.rawAddress ?? Uint8List.fromList(ascii.encode(host));
        }).toList(),
      );
      extension.elements![extension.elements!.length - 1] = ASN1OctetString(
        octets: names.encode(),
      );
    }
    for (final extension in extensions.elements!.cast<ASN1Sequence>()) {
      extension.encodedBytes = null;
    }
    extensions.encodedBytes = null;
    tbs.elements![tbs.elements!.length - 1] = ASN1Object(tag: 0xA3)
      ..valueBytes = extensions.encode();
    tbs.encodedBytes = null;
    final signature = CryptoUtils.rsaSign(privateKey, tbs.encode());
    outer.elements![2] = ASN1BitString(stringValues: signature);
    outer.encodedBytes = null;
    return (
      X509Utils.encodeASN1ObjectToPem(
        outer,
        '-----BEGIN CERTIFICATE-----',
        '-----END CERTIFICATE-----',
      ),
      CryptoUtils.encodeRSAPrivateKeyToPem(privateKey),
    );
  }

  static String _randomId() => List.generate(
    16,
    (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();

  static Future<void> _writePrivate(File file, String contents) async {
    await file.create(exclusive: true);
    await _restrict(file.path, '600');
    await file.writeAsString(contents, flush: true);
  }

  static Future<void> _restrict(String path, String mode) async {
    if (Platform.isWindows) return;
    final result = await Process.run('chmod', [mode, path]);
    if (result.exitCode != 0) throw const FileSystemException('无法保护 TLS 文件权限。');
  }
}
