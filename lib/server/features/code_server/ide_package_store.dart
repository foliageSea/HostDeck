import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

import 'package:host_deck/server/features/code_server/code_server_models.dart';

/// code-server 离线安装包存储。
///
/// 目录布局（`root` 由调用方传入，生产环境为 `<dataDir>/code-server`）：
/// ```
/// <root>/packages/<version>/linux-<arch>.tar.gz   安装包本体
/// <root>/packages/<version>/<id>.json             元数据 sidecar
/// <root>/offline/                                 手工投放的离线包，由 [scan] 导入
/// <root>/tmp/                                     上传临时文件（由 controller 使用）
/// ```
///
/// 包 ID 规则：`<version>-linux-<arch>`。
///
/// 存储层只负责落盘与校验，不解析数据目录、不缓存全局状态；所有操作对
/// 缺失目录、损坏 sidecar、并发删除保持容忍（[list] 不抛异常）。
class IdePackageStore {
  static final RegExp _versionPattern = RegExp(r'^[0-9A-Za-z][0-9A-Za-z.+_]*$');
  static final RegExp _archPattern = RegExp(r'^[A-Za-z0-9_]+$');
  static final RegExp _sha256Pattern = RegExp(r'^[0-9a-f]{64}$');
  static final RegExp _idPattern = RegExp(r'^(.+)-linux-([A-Za-z0-9_]+)$');
  static final RegExp _offlineFileNamePattern = RegExp(
    r'^(?:hostdeck-)?code-server-(.+?)-linux-([A-Za-z0-9_]+)\.tar\.gz$',
  );

  final Directory _root;
  final Logger _log;

  IdePackageStore(Directory root, {Logger? log})
    : _root = root,
      _log = log ?? Logger('IdePackageStore');

  /// 存储根目录。
  Directory get root => _root;

  Directory get _packagesDir => Directory(p.join(_root.path, 'packages'));

  Directory get _offlineDir => Directory(p.join(_root.path, 'offline'));

  String _versionDir(String version) => p.join(_packagesDir.path, version);

  String _sidecarPath(String version, String id) =>
      p.join(_versionDir(version), '$id.json');

  /// 列出已导入的离线包，按导入时间倒序。
  ///
  /// 目录不存在、sidecar 损坏或安装包缺失时跳过对应条目，绝不抛异常。
  Future<List<IdePackage>> list() async {
    final packages = <IdePackage>[];
    try {
      if (!await _packagesDir.exists()) return packages;
      await for (final entry in _packagesDir.list(followLinks: false)) {
        if (entry is! Directory) continue;
        await for (final file in entry.list(followLinks: false)) {
          if (file is! File || p.extension(file.path) != '.json') continue;
          final package = await _readSidecar(file, expectedDir: entry);
          if (package != null) packages.add(package);
        }
      }
    } on FileSystemException catch (error, stackTrace) {
      _log.warning('读取离线包目录失败：${_packagesDir.path}', error, stackTrace);
    }
    packages.sort((a, b) {
      final byTime = b.createdAt.compareTo(a.createdAt);
      return byTime != 0 ? byTime : a.id.compareTo(b.id);
    });
    return packages;
  }

  /// 按版本与架构查找离线包，不存在或元数据损坏时返回 null。
  Future<IdePackage?> find({
    required String version,
    required String arch,
  }) async {
    _validate(version, arch);
    final id = IdePackage.buildId(version: version, arch: arch);
    final sidecar = File(_sidecarPath(version, id));
    if (!await sidecar.exists()) return null;
    final package = await _readSidecar(
      sidecar,
      expectedDir: Directory(_versionDir(version)),
    );
    return package?.id == id ? package : null;
  }

  /// 导入调用方写好的临时文件（与存储同盘）。
  ///
  /// 流式计算 sha256、校验 [sha256] 与文件大小，随后以原子 rename 移动到
  /// `<root>/packages/<version>/linux-<arch>.tar.gz` 并写入 sidecar。
  /// 同一份内容重复导入是幂等的：直接返回已有元数据并清理临时文件。
  ///
  /// 参数不合法、文件不存在/为空、sha256 不匹配时抛 [ArgumentError]。
  Future<IdePackage> importFile(
    File source, {
    required String version,
    required String arch,
    String? sha256,
  }) async {
    _validate(version, arch);
    if (!await source.exists()) {
      throw ArgumentError.value(source.path, 'source', '离线包源文件不存在');
    }
    final expectedSha = sha256?.trim().toLowerCase();
    if (expectedSha != null && !_sha256Pattern.hasMatch(expectedSha)) {
      throw ArgumentError.value(sha256, 'sha256', 'sha256 必须是 64 位十六进制字符串');
    }

    final size = await source.length();
    if (size == 0) {
      throw ArgumentError.value(source.path, 'source', '离线包内容为空');
    }
    final digest = await _sha256Of(source);
    if (expectedSha != null && expectedSha != digest) {
      throw ArgumentError.value(
        sha256,
        'sha256',
        'sha256 校验失败：期望 $expectedSha，实际 $digest',
      );
    }

    final id = IdePackage.buildId(version: version, arch: arch);
    final dir = Directory(_versionDir(version));
    final sidecar = File(_sidecarPath(version, id));
    final artifact = File(p.join(dir.path, 'linux-$arch.tar.gz'));
    final existing = await _readSidecar(sidecar, expectedDir: dir);

    if (existing != null && existing.sha256 == digest) {
      _log.info('离线包 $id 已存在且内容一致，跳过导入');
      if (!p.equals(source.absolute.path, artifact.absolute.path)) {
        await _deleteQuietly(source);
      }
      return existing;
    }

    await dir.create(recursive: true);
    // 先让旧元数据失效，避免 rename 与写 sidecar 之间出现指向旧包的中间态。
    await _deleteQuietly(sidecar);
    try {
      await source.rename(artifact.path);
    } on FileSystemException {
      // 跨文件系统时 rename 不可用：同目录写临时副本，再用 rename 原子替换。
      _log.fine('源文件与包目录跨文件系统，改用复制后 rename：${source.path}');
      final staging = File(
        '${artifact.path}.tmp-${DateTime.now().microsecondsSinceEpoch}',
      );
      try {
        await source.copy(staging.path);
        await staging.rename(artifact.path);
      } finally {
        await _deleteQuietly(staging);
      }
      await _deleteQuietly(source);
    }

    final package = IdePackage(
      id: id,
      version: version,
      arch: arch,
      path: artifact.path,
      size: size,
      sha256: digest,
      createdAt: DateTime.now(),
    );
    try {
      await _writeSidecar(sidecar, package);
    } catch (error, stackTrace) {
      _log.severe('写入离线包元数据失败：${sidecar.path}', error, stackTrace);
      rethrow;
    }
    _log.info('已导入离线包 $id（$size 字节，sha256=$digest）');
    return package;
  }

  /// 删除离线包。ID 合法但包不存在时视为已删除（幂等）。
  ///
  /// ID 格式不合法时抛 [ArgumentError]。
  Future<void> delete(String id) async {
    final trimmed = id.trim();
    final match = _idPattern.firstMatch(trimmed);
    if (match == null) {
      throw ArgumentError.value(id, 'id', '离线包 ID 必须形如 <version>-linux-<arch>');
    }
    final version = match.group(1)!;
    final arch = match.group(2)!;
    _validate(version, arch);
    final expectedId = IdePackage.buildId(version: version, arch: arch);
    if (expectedId != trimmed) {
      throw ArgumentError.value(id, 'id', '离线包 ID 不合法');
    }

    final dir = Directory(_versionDir(version));
    final artifact = File(p.join(dir.path, 'linux-$arch.tar.gz'));
    final sidecar = File(_sidecarPath(version, expectedId));
    var removed = false;
    for (final file in [artifact, sidecar]) {
      if (await file.exists()) {
        await file.delete();
        removed = true;
      }
    }
    if (!removed) {
      _log.fine('离线包 $expectedId 不存在，忽略删除');
      return;
    }
    try {
      if (await dir.exists() && await dir.list(followLinks: false).isEmpty) {
        await dir.delete();
      }
    } on FileSystemException catch (error) {
      _log.fine('保留非空的离线包目录：${dir.path}', error);
    }
    _log.info('已删除离线包 $expectedId');
  }

  /// 扫描 `<root>/offline`，把手工投放的安装包导入存储并返回导入结果。
  ///
  /// 文件名须为 `code-server-<version>-linux-<arch>.tar.gz` 或
  /// `hostdeck-code-server-<version>-linux-<arch>.tar.gz`；非 tar.gz 文件
  /// 与隐藏文件会被忽略，形似安装包但文件名不合法时抛 [ArgumentError]。
  Future<List<IdePackage>> scan() async {
    final imported = <IdePackage>[];
    if (!await _offlineDir.exists()) return imported;
    await for (final entry in _offlineDir.list(followLinks: false)) {
      if (entry is! File) continue;
      final name = p.basename(entry.path);
      if (name.startsWith('.')) continue;
      if (!name.endsWith('.tar.gz')) {
        _log.fine('忽略离线包目录中的非安装包文件：$name');
        continue;
      }
      final parsed = parseOfflineFileName(name);
      imported.add(
        await importFile(entry, version: parsed.version, arch: parsed.arch),
      );
    }
    _log.info('扫描 ${_offlineDir.path}，导入 ${imported.length} 个离线包');
    return imported;
  }

  /// 已导入离线包占用的磁盘字节数。
  Future<int> totalBytes() async {
    var total = 0;
    for (final package in await list()) {
      try {
        total += await File(package.path).length();
      } on FileSystemException catch (error) {
        _log.fine('统计离线包大小时跳过不可读文件：${package.path}', error);
      }
    }
    return total;
  }

  /// 解析离线包文件名，返回版本与架构。
  ///
  /// 支持 `code-server-<version>-linux-<arch>.tar.gz` 与
  /// `hostdeck-code-server-<version>-linux-<arch>.tar.gz`；
  /// 文件名不匹配时抛 [ArgumentError]。
  static ({String version, String arch}) parseOfflineFileName(String fileName) {
    final match = _offlineFileNamePattern.firstMatch(p.basename(fileName));
    if (match == null) {
      throw ArgumentError.value(
        fileName,
        'fileName',
        '离线包文件名必须形如 code-server-<version>-linux-<arch>.tar.gz',
      );
    }
    final version = match.group(1)!;
    final arch = match.group(2)!;
    if (!_versionPattern.hasMatch(version) || !_archPattern.hasMatch(arch)) {
      throw ArgumentError.value(
        fileName,
        'fileName',
        '离线包文件名中的 version 或 arch 不合法',
      );
    }
    return (version: version, arch: arch);
  }

  /// 读取 sidecar；损坏、缺失或与目录/文件名不一致时返回 null。
  Future<IdePackage?> _readSidecar(
    File sidecar, {
    Directory? expectedDir,
  }) async {
    try {
      final decoded = jsonDecode(await sidecar.readAsString());
      if (decoded is! Map<String, dynamic>) return null;
      final metadata = IdePackage.fromJson(decoded);
      final id = IdePackage.buildId(
        version: metadata.version,
        arch: metadata.arch,
      );
      if (id != metadata.id) return null;
      if (p.basenameWithoutExtension(sidecar.path) != id) return null;
      final dir = expectedDir ?? Directory(_versionDir(metadata.version));
      if (p.basename(dir.path) != metadata.version) return null;
      final artifact = File(p.join(dir.path, 'linux-${metadata.arch}.tar.gz'));
      if (!await artifact.exists()) return null;
      return IdePackage(
        id: id,
        version: metadata.version,
        arch: metadata.arch,
        path: artifact.path,
        size: await artifact.length(),
        sha256: metadata.sha256,
        createdAt: metadata.createdAt,
      );
    } catch (error, stackTrace) {
      _log.fine('忽略损坏的离线包元数据：${sidecar.path}', error, stackTrace);
      return null;
    }
  }

  /// 先写同目录临时文件，再原子 rename 成 sidecar。
  Future<void> _writeSidecar(File sidecar, IdePackage package) async {
    await sidecar.parent.create(recursive: true);
    final staging = File(
      '${sidecar.path}.tmp-${DateTime.now().microsecondsSinceEpoch}',
    );
    try {
      await staging.writeAsString(jsonEncode(package.toJson()), flush: true);
      await staging.rename(sidecar.path);
    } finally {
      await _deleteQuietly(staging);
    }
  }

  /// 流式计算 sha256，避免把整包读入内存。
  Future<String> _sha256Of(File file) async {
    final sink = _DigestSink();
    final input = sha256.startChunkedConversion(sink);
    try {
      await for (final chunk in file.openRead()) {
        input.add(chunk);
      }
    } finally {
      input.close();
    }
    return sink.value.toString();
  }

  Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException catch (error) {
      _log.fine('删除临时文件失败：${file.path}', error);
    }
  }

  void _validate(String version, String arch) {
    if (!_versionPattern.hasMatch(version)) {
      throw ArgumentError.value(
        version,
        'version',
        'version 只能由字母、数字、点、加号或下划线组成（例如 4.101.2）',
      );
    }
    if (!_archPattern.hasMatch(arch)) {
      throw ArgumentError.value(
        arch,
        'arch',
        'arch 只能由字母、数字或下划线组成（例如 amd64、arm64）',
      );
    }
  }
}

/// 收集 [sha256] 分块摘要的 sink。
class _DigestSink implements Sink<Digest> {
  Digest? _digest;

  Digest get value {
    final digest = _digest;
    if (digest == null) {
      throw StateError('sha256 未产生摘要');
    }
    return digest;
  }

  @override
  void add(Digest data) {
    _digest = data;
  }

  @override
  void close() {}
}
