import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:host_deck_sidecar/protocol.dart';
import 'package:host_deck_sidecar/src/archive_operations.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory root;
  late Directory stage;
  late File zip;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('sidecar-zip-links-test-');
    stage = await Directory(p.join(root.path, 'stage')).create();
    zip = File(p.join(root.path, 'members.zip'));
  });
  tearDown(() => root.delete(recursive: true));

  Future<void> extract([void Function(SidecarProgress)? progress]) =>
      extractSidecarArchive(
        archivePath: zip.path,
        staging: stage,
        cancellation: SidecarCancellation(),
        onProgress: progress ?? (_) {},
      );

  test(
    'stores only original link metadata and excludes it from progress',
    () async {
      const linkTarget = '\uFEFF档';
      final sourceDir = await Directory(p.join(root.path, 'source')).create();
      final source = await File(
        p.join(sourceDir.path, linkTarget),
      ).writeAsString('body');
      final link = await Link(
        p.join(sourceDir.path, 'alias'),
      ).create(linkTarget);
      ArchiveSourceEntry entry(
        FileSystemEntity entity,
        String name,
        int size, {
        String? linkTarget,
      }) => ArchiveSourceEntry(
        path: entity.path,
        name: name,
        isDirectory: entity is Directory,
        size: size,
        mode: 0x1ff,
        modified: DateTime.utc(2024, 1, 1),
        linkTarget: linkTarget,
      );
      final createProgress = <SidecarProgress>[];
      await createSidecarArchive(
        entries: [
          entry(link, 'dir/alias', 0, linkTarget: linkTarget),
          entry(sourceDir, 'dir', 0),
          entry(source, 'dir/$linkTarget', 4),
        ],
        archivePath: zip.path,
        formatPath: zip.path,
        staging: root,
        cancellation: SidecarCancellation(),
        onProgress: createProgress.add,
      );
      final bytes = await zip.readAsBytes();
      final header = ByteData.sublistView(bytes);
      final central = _centralOffset(bytes);
      final dataOffset =
          30 + header.getUint16(26, _le) + header.getUint16(28, _le);
      final encodedTarget = utf8.encode(linkTarget);
      expect(header.getUint16(8, _le), 0); // Store
      expect(header.getUint32(22, _le), encodedTarget.length);
      expect(header.getUint8(central + 5), 3); // Unix
      expect(header.getUint32(central + 38, _le) >> 28, 0xa);
      expect(
        bytes.sublist(dataOffset, dataOffset + encodedTarget.length),
        encodedTarget,
      );

      final extractProgress = <SidecarProgress>[];
      await extract(extractProgress.add);
      expect(
        await Link(p.join(stage.path, 'dir', 'alias')).target(),
        linkTarget,
      );
      expect(
        await File(p.join(stage.path, 'dir', 'alias')).readAsString(),
        'body',
      );
      for (final updates in [createProgress, extractProgress]) {
        expect(
          updates
              .where((v) => v.bytesTotal != null)
              .map((v) => v.bytesTotal)
              .toSet(),
          {4},
        );
        expect(updates.firstWhere((v) => v.entriesDone == 1).bytesDone, 0);
        expect(updates.last.bytesDone, 4);
        expect(updates.last.entriesDone, 3);
        expect(updates.last.entriesTotal, 3);
      }
    },
    skip: Platform.isWindows,
  );

  test('accepts a deflated Unix link with a later target', () async {
    final target = List.filled(100, 'a').join();
    final bytes = _unixLinkFixture(
      './$target',
      deflate: true,
      regularTarget: target,
    );
    expect(ByteData.sublistView(bytes).getUint16(8, _le), 8);
    await zip.writeAsBytes(bytes);
    await extract();
    expect(await Link(p.join(stage.path, 'alias')).target(), './$target');
    expect(await File(p.join(stage.path, 'alias')).readAsString(), 'body');
  }, skip: Platform.isWindows);

  test('reads a relative symlink produced by Info-ZIP -y', () async {
    final subdir = await Directory(p.join(root.path, 'subdir')).create();
    await File(p.join(root.path, 'target')).writeAsString('body');
    await Link(p.join(subdir.path, 'alias')).create('.././target');
    final ProcessResult result;
    try {
      result = await Process.run('zip', [
        '-y',
        zip.path,
        'subdir/',
        'subdir/alias',
        'target',
      ], workingDirectory: root.path);
    } on ProcessException {
      markTestSkipped('Info-ZIP is not installed');
      return;
    }
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    await extract();
    expect(
      await Link(p.join(stage.path, 'subdir', 'alias')).target(),
      '.././target',
    );
  }, skip: Platform.isWindows);

  test(
    'rejects link targets exceeding the byte limit before materializing',
    () async {
      await zip.writeAsBytes(
        _unixLinkFixture(List.filled(4097, 'a').join(), deflate: true),
      );
      await expectLater(extract(), _failure('archive_limit'));
      expect(await stage.list().isEmpty, isTrue);
    },
  );

  test('validates declared link size and CRC before materializing', () async {
    final overrun = _unixLinkFixture('./target', deflate: true);
    ByteData.sublistView(overrun)
      ..setUint32(22, 1, _le)
      ..setUint32(_centralOffset(overrun) + 24, 1, _le);
    await zip.writeAsBytes(overrun);
    await expectLater(extract(), _failure('archive_invalid'));

    final badCrc = _unixLinkFixture('./target');
    final header = ByteData.sublistView(badCrc);
    badCrc[30 + header.getUint16(26, _le) + header.getUint16(28, _le)] ^= 1;
    await zip.writeAsBytes(badCrc);
    await expectLater(extract(), _failure('archive_invalid'));
    expect(await stage.list().isEmpty, isTrue);
  });

  test('rejects unsupported host, type, and special attributes', () async {
    for (final (host, attributes) in [
      (0, 0xa1ff0000), // Unix link mode declared under MS-DOS.
      (3, 0x21ff0000), // Character device, not a link.
      (3, 0xa1ff0400), // DOS reparse point.
    ]) {
      final bytes = _unixLinkFixture('./target', regularTarget: 'target');
      final central = _centralOffset(bytes);
      ByteData.sublistView(bytes)
        ..setUint8(central + 5, host)
        ..setUint32(central + 38, attributes, _le);
      await zip.writeAsBytes(bytes);
      await expectLater(extract(), _failure('archive_unsafe'));
    }
    expect(await stage.list().isEmpty, isTrue);
  });
}

const _le = Endian.little;

int _centralOffset(Uint8List bytes) =>
    ByteData.sublistView(bytes).getUint32(bytes.length - 6, _le);

Matcher _failure(String code) =>
    throwsA(isA<SidecarException>().having((e) => e.code, 'code', code));

Uint8List _unixLinkFixture(
  String target, {
  bool deflate = false,
  String? regularTarget,
}) {
  final member = ArchiveFile.string('alias', target)
    ..mode = 0xa1ff
    ..compression = deflate ? CompressionType.deflate : CompressionType.none;
  final archive = Archive()..add(member);
  if (regularTarget != null) {
    archive.add(ArchiveFile.string(regularTarget, 'body'));
  }
  final bytes = Uint8List.fromList(ZipEncoder().encode(archive));
  // ZipEncoder preserves the mode but always emits the MS-DOS creator code.
  ByteData.sublistView(bytes).setUint8(_centralOffset(bytes) + 5, 3);
  return bytes;
}
