import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:host_deck/server/features/code_server/code_server_models.dart';
import 'package:host_deck/server/features/code_server/ide_package_store.dart';

const _version = '4.101.2';
const _arch = 'amd64';
const _id = '4.101.2-linux-amd64';

final List<int> _payloadA = utf8.encode('hostdeck code-server package A');
final List<int> _payloadB = utf8.encode('hostdeck code-server package B');

String _sha256(List<int> bytes) => sha256.convert(bytes).toString();

void main() {
  late Directory tempRoot;
  late IdePackageStore store;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('hostdeck_pkg_store_');
    store = IdePackageStore(tempRoot);
  });

  tearDown(() async {
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  Future<File> writeIncoming(String name, List<int> bytes) async {
    final dir = Directory(p.join(tempRoot.path, 'tmp'));
    await dir.create(recursive: true);
    final file = File(p.join(dir.path, name));
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  /// 按本模块约定的磁盘布局直接写一个「已导入」的离线包。
  Future<IdePackage> writeManagedPackage({
    required String version,
    required String arch,
    required List<int> bytes,
    required DateTime createdAt,
  }) async {
    final id = IdePackage.buildId(version: version, arch: arch);
    final dir = Directory(p.join(tempRoot.path, 'packages', version));
    await dir.create(recursive: true);
    final artifact = File(p.join(dir.path, 'linux-$arch.tar.gz'));
    await artifact.writeAsBytes(bytes, flush: true);
    final package = IdePackage(
      id: id,
      version: version,
      arch: arch,
      path: artifact.path,
      size: bytes.length,
      sha256: _sha256(bytes),
      createdAt: createdAt,
    );
    await File(
      p.join(dir.path, '$id.json'),
    ).writeAsString(jsonEncode(package.toJson()));
    return package;
  }

  group('importFile', () {
    test('按 <version>/linux-<arch>.tar.gz 落盘并写入 sidecar', () async {
      final source = await writeIncoming('upload-1.tar.gz', _payloadA);
      final package = await store.importFile(
        source,
        version: _version,
        arch: _arch,
      );

      expect(package.id, _id);
      expect(package.version, _version);
      expect(package.arch, _arch);
      expect(package.size, _payloadA.length);
      expect(package.sha256, _sha256(_payloadA));
      expect(package.fileName, 'linux-amd64.tar.gz');
      expect(
        package.path,
        p.join(tempRoot.path, 'packages', _version, 'linux-amd64.tar.gz'),
      );
      expect(await File(package.path).exists(), isTrue);
      expect(await source.exists(), isFalse, reason: '临时文件应被原子移动');

      final sidecar = File(
        p.join(tempRoot.path, 'packages', _version, '$_id.json'),
      );
      expect(await sidecar.exists(), isTrue);
      final decoded = jsonDecode(await sidecar.readAsString());
      expect(decoded, isA<Map<String, dynamic>>());
      expect((decoded as Map<String, dynamic>)['sha256'], package.sha256);
      expect(decoded['id'], _id);
      expect(await File(package.path).length(), _payloadA.length);
    });

    test('sha256 可选参数匹配时导入、校验失败时抛 ArgumentError', () async {
      final okSource = await writeIncoming('upload-ok.tar.gz', _payloadA);
      final package = await store.importFile(
        okSource,
        version: _version,
        arch: _arch,
        sha256: _sha256(_payloadA),
      );
      expect(package.sha256, _sha256(_payloadA));

      final badSource = await writeIncoming('upload-bad.tar.gz', _payloadA);
      await expectLater(
        store.importFile(
          badSource,
          version: '4.101.3',
          arch: 'arm64',
          sha256: '0' * 64,
        ),
        throwsArgumentError,
      );
      expect(await badSource.exists(), isTrue, reason: '校验失败不应移动源文件');

      final targetDir = Directory(p.join(tempRoot.path, 'packages', '4.101.3'));
      expect(await targetDir.exists(), isFalse);

      await expectLater(
        store.importFile(
          badSource,
          version: '4.101.4',
          arch: 'amd64',
          sha256: 'not-a-sha256',
        ),
        throwsArgumentError,
      );
    });

    test('空文件、缺失源文件、非法 version/arch 抛 ArgumentError', () async {
      final empty = await writeIncoming('empty.tar.gz', const []);
      await expectLater(
        store.importFile(empty, version: _version, arch: _arch),
        throwsArgumentError,
      );

      final missing = File(p.join(tempRoot.path, 'tmp', 'missing.tar.gz'));
      await expectLater(
        store.importFile(missing, version: _version, arch: _arch),
        throwsArgumentError,
      );

      final source = await writeIncoming('upload-2.tar.gz', _payloadA);
      await expectLater(
        store.importFile(source, version: '../4.101.2', arch: _arch),
        throwsArgumentError,
      );
      await expectLater(
        store.importFile(source, version: _version, arch: 'amd64/x'),
        throwsArgumentError,
      );
      await expectLater(
        store.importFile(source, version: '', arch: _arch),
        throwsArgumentError,
      );
    });

    test('重复导入相同内容是幂等的', () async {
      final first = await store.importFile(
        await writeIncoming('upload-a.tar.gz', _payloadA),
        version: _version,
        arch: _arch,
      );
      final second = await store.importFile(
        await writeIncoming('upload-b.tar.gz', _payloadA),
        version: _version,
        arch: _arch,
      );

      expect(second.id, first.id);
      expect(second.sha256, first.sha256);
      expect(second.createdAt, first.createdAt);
      expect((await store.list()).length, 1);
      expect(
        await File(p.join(tempRoot.path, 'tmp', 'upload-b.tar.gz')).exists(),
        isFalse,
        reason: '重复上传的临时文件应被清理',
      );
    });

    test('重复导入不同内容会替换旧包', () async {
      final first = await store.importFile(
        await writeIncoming('upload-a.tar.gz', _payloadA),
        version: _version,
        arch: _arch,
      );
      final second = await store.importFile(
        await writeIncoming('upload-b.tar.gz', _payloadB),
        version: _version,
        arch: _arch,
      );

      expect(second.sha256, _sha256(_payloadB));
      expect(second.sha256, isNot(first.sha256));
      expect(
        await File(
          p.join(tempRoot.path, 'packages', _version, 'linux-amd64.tar.gz'),
        ).readAsBytes(),
        _payloadB,
      );
      final packages = await store.list();
      expect(packages.length, 1);
      expect(packages.single.sha256, _sha256(_payloadB));
    });
  });

  group('list / find', () {
    test('目录不存在时返回空列表', () async {
      expect(await store.list(), isEmpty);
      final fresh = await Directory.systemTemp.createTemp(
        'hostdeck_pkg_empty_',
      );
      addTearDown(() => fresh.delete(recursive: true));
      expect(await IdePackageStore(fresh).list(), isEmpty);
    });

    test('按 createdAt 倒序返回并容忍损坏 sidecar/缺失安装包', () async {
      await writeManagedPackage(
        version: '4.101.2',
        arch: 'amd64',
        bytes: _payloadA,
        createdAt: DateTime.utc(2026, 1, 1),
      );
      await writeManagedPackage(
        version: '4.101.3',
        arch: 'arm64',
        bytes: _payloadB,
        createdAt: DateTime.utc(2026, 2, 1),
      );

      // 损坏的 sidecar
      await File(
        p.join(
          tempRoot.path,
          'packages',
          '4.101.2',
          '4.101.2-linux-arm64.json',
        ),
      ).writeAsString('{not json');
      // 声明了包但安装包文件缺失
      await File(
        p.join(
          tempRoot.path,
          'packages',
          '4.101.3',
          '4.101.3-linux-amd64.json',
        ),
      ).writeAsString(
        jsonEncode(
          IdePackage(
            id: '4.101.3-linux-amd64',
            version: '4.101.3',
            arch: 'amd64',
            path: p.join(
              tempRoot.path,
              'packages',
              '4.101.3',
              'linux-amd64.tar.gz',
            ),
            size: 1,
            sha256: '0' * 64,
            createdAt: DateTime.utc(2026, 3, 1),
          ).toJson(),
        ),
      );

      final packages = await store.list();
      expect(packages.map((item) => item.id), ['4.101.3-linux-arm64', _id]);
      expect(packages.first.createdAt, DateTime.utc(2026, 2, 1));
      expect(packages.last.path, endsWith('linux-amd64.tar.gz'));
    });

    test('find 命中已导入包，缺失或损坏返回 null', () async {
      expect(await store.find(version: _version, arch: _arch), isNull);

      final package = await store.importFile(
        await writeIncoming('upload.tar.gz', _payloadA),
        version: _version,
        arch: _arch,
      );
      final found = await store.find(version: _version, arch: _arch);
      expect(found?.id, package.id);
      expect(found?.sha256, package.sha256);
      expect(await store.find(version: _version, arch: 'arm64'), isNull);

      final sidecar = File(
        p.join(tempRoot.path, 'packages', _version, '$_id.json'),
      );
      await sidecar.writeAsString('broken');
      expect(await store.find(version: _version, arch: _arch), isNull);
    });
  });

  group('delete', () {
    test('删除安装包与 sidecar，并清理空版本目录', () async {
      final package = await store.importFile(
        await writeIncoming('upload.tar.gz', _payloadA),
        version: _version,
        arch: _arch,
      );
      await store.delete(package.id);

      expect(await File(package.path).exists(), isFalse);
      expect(
        await File(
          p.join(tempRoot.path, 'packages', _version, '$_id.json'),
        ).exists(),
        isFalse,
      );
      expect(
        await Directory(p.join(tempRoot.path, 'packages', _version)).exists(),
        isFalse,
      );
      expect(await store.list(), isEmpty);
    });

    test('未知 ID 幂等，格式非法抛 ArgumentError', () async {
      await store.importFile(
        await writeIncoming('upload.tar.gz', _payloadA),
        version: _version,
        arch: _arch,
      );
      await store.delete('9.9.9-linux-amd64');
      expect((await store.list()).length, 1);

      await expectLater(store.delete('garbage'), throwsArgumentError);
      await expectLater(
        store.delete('../4.101.2-linux-amd64'),
        throwsArgumentError,
      );
    });
  });

  group('scan', () {
    test('从 offline 导入 code-server 与 hostdeck-code-server 两种命名', () async {
      final offline = Directory(p.join(tempRoot.path, 'offline'));
      await offline.create(recursive: true);
      await File(
        p.join(offline.path, 'code-server-4.101.2-linux-amd64.tar.gz'),
      ).writeAsBytes(_payloadA, flush: true);
      await File(
        p.join(offline.path, 'hostdeck-code-server-4.101.3-linux-arm64.tar.gz'),
      ).writeAsBytes(_payloadB, flush: true);

      final imported = await store.scan();
      expect(imported.map((item) => item.id), [
        '4.101.2-linux-amd64',
        '4.101.3-linux-arm64',
      ]);
      expect(
        await File(
          p.join(tempRoot.path, 'packages', '4.101.3', 'linux-arm64.tar.gz'),
        ).exists(),
        isTrue,
      );
      expect(
        await File(
          p.join(offline.path, 'code-server-4.101.2-linux-amd64.tar.gz'),
        ).exists(),
        isFalse,
        reason: '导入后离线包应移入存储目录',
      );
      expect((await store.list()).length, 2);

      // 再次扫描同一目录不会重复导入。
      expect(await store.scan(), isEmpty);
      expect((await store.list()).length, 2);
    });

    test('忽略无关文件与缺失目录，非法包名抛 ArgumentError', () async {
      expect(await store.scan(), isEmpty);

      final offline = Directory(p.join(tempRoot.path, 'offline'));
      await offline.create(recursive: true);
      await File(p.join(offline.path, 'README.md')).writeAsString('readme');
      await File(p.join(offline.path, '.DS_Store')).writeAsString('');
      await File(
        p.join(offline.path, 'code-server-4.101.2-linux-amd64.tar.gz.part'),
      ).writeAsBytes(_payloadA, flush: true);

      expect(await store.scan(), isEmpty);

      await File(
        p.join(offline.path, 'code-server-linux-amd64.tar.gz'),
      ).writeAsBytes(_payloadA, flush: true);
      await expectLater(store.scan(), throwsArgumentError);
    });
  });

  test('totalBytes 汇总已导入安装包大小', () async {
    expect(await store.totalBytes(), 0);

    await store.importFile(
      await writeIncoming('upload-a.tar.gz', _payloadA),
      version: '4.101.2',
      arch: 'amd64',
    );
    await store.importFile(
      await writeIncoming('upload-b.tar.gz', _payloadB),
      version: '4.101.4',
      arch: 'amd64',
    );

    expect(await store.totalBytes(), _payloadA.length + _payloadB.length);
  });

  test('parseOfflineFileName 解析两种命名，非法文件名抛 ArgumentError', () {
    final plain = IdePackageStore.parseOfflineFileName(
      'code-server-4.101.2-linux-amd64.tar.gz',
    );
    expect(plain.version, '4.101.2');
    expect(plain.arch, 'amd64');

    final prefixed = IdePackageStore.parseOfflineFileName(
      '/data/offline/hostdeck-code-server-4.101.3-linux-arm64.tar.gz',
    );
    expect(prefixed.version, '4.101.3');
    expect(prefixed.arch, 'arm64');

    expect(
      () => IdePackageStore.parseOfflineFileName('code-server.tar.gz'),
      throwsArgumentError,
    );
    expect(
      () => IdePackageStore.parseOfflineFileName(
        'code-server-4.101.2-linux-amd64.zip',
      ),
      throwsArgumentError,
    );
  });
}
