import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:host_deck_sidecar/protocol.dart';
import 'package:host_deck_sidecar/src/archive_operations.dart';
import 'package:path/path.dart' as p;
import 'package:tar/tar.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;
  late Directory stage;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('sidecar-archive-test-');
    stage = await Directory(p.join(root.path, 'stage')).create();
  });
  tearDown(() => root.delete(recursive: true));

  ArchiveSourceEntry entry(FileSystemEntity entity, String name, int size) =>
      ArchiveSourceEntry(
        path: entity.path,
        name: name,
        isDirectory: entity is Directory,
        size: size,
        mode: 0x1a4,
        modified: DateTime.utc(2024, 1, 1),
      );

  Future<void> create(
    String format,
    List<ArchiveSourceEntry> entries, {
    SidecarCancellation? cancellation,
    void Function(SidecarProgress)? progress,
  }) => createSidecarArchive(
    entries: entries,
    archivePath: p.join(root.path, format),
    formatPath: format,
    staging: root,
    cancellation: cancellation ?? SidecarCancellation(),
    onProgress: progress ?? (_) {},
  );

  Future<void> extract(
    String name, {
    SidecarCancellation? cancellation,
    void Function(SidecarProgress)? progress,
  }) => extractSidecarArchive(
    archivePath: p.join(root.path, name),
    staging: stage,
    cancellation: cancellation ?? SidecarCancellation(),
    onProgress: progress ?? (_) {},
  );

  Matcher failure(String code) =>
      throwsA(isA<SidecarException>().having((e) => e.code, 'code', code));

  Future<void> writeTar(String name, List<SynchronousTarEntry> entries) async {
    final sink = _BytesSink();
    final encoder = tarConverter.startChunkedConversion(sink);
    for (final entry in entries) {
      encoder.add(entry);
    }
    encoder.close();
    final bytes = sink.builder.takeBytes();
    await File(
      p.join(root.path, name),
    ).writeAsBytes(name.endsWith('.tar') ? bytes : gzip.encode(bytes));
  }

  SynchronousTarEntry tarEntry(
    String name,
    List<int> data, {
    TypeFlag? type,
    String? link,
  }) => TarEntry.data(
    TarHeader(name: name, mode: 0x1a4, typeFlag: type, linkName: link),
    data,
  );

  for (final extension in ['zip', 'tar.gz', 'tgz']) {
    test(
      'create/extract .$extension with exact, monotonic streamed bytes',
      () async {
        final input = await Directory(p.join(root.path, 'input')).create();
        final random = Random(101);
        final data = Uint8List.fromList(
          List.generate(350000, (_) => random.nextInt(256)),
        );
        final file = await File(
          p.join(input.path, 'source'),
        ).writeAsBytes(data);
        final empty = await File(p.join(input.path, 'empty')).create();
        final filename = '归档${List.filled(110, 'a').join()}';
        final created = <SidecarProgress>[];
        final extracted = <SidecarProgress>[];
        final format = 'test.$extension';
        await create(format, [
          entry(input, 'one', 0),
          entry(file, 'one/$filename', data.length),
          entry(empty, 'one/empty', 0),
        ], progress: created.add);
        final archive = File(p.join(root.path, format));
        if (extension == 'zip') {
          final decoded = ZipDecoder().decodeBytes(await archive.readAsBytes());
          expect(decoded.find('one/$filename')?.content, orderedEquals(data));
        } else {
          final reader = TarReader(
            gzip.decoder.bind(archive.openRead()),
            maxSpecialFileSize: 8192,
          );
          try {
            expect(await reader.moveNext(), isTrue);
            expect(reader.current.header.name, 'one/');
            expect(await reader.moveNext(), isTrue);
            expect(reader.current.header.name, 'one/$filename');
            final bytes = BytesBuilder();
            await reader.current.contents.forEach(bytes.add);
            expect(bytes.takeBytes(), orderedEquals(data));
          } finally {
            await reader.cancel();
          }
        }
        await extract(format, progress: extracted.add);
        expect(
          await File(p.join(stage.path, 'one', filename)).readAsBytes(),
          orderedEquals(data),
        );
        expect(await File(p.join(stage.path, 'one', 'empty')).length(), 0);
        for (final updates in [created, extracted]) {
          expect(updates.first.bytesDone, 0);
          expect(updates.last.bytesDone, data.length);
          expect(updates.last.bytesTotal, data.length);
          expect(updates.last.entriesDone, 3);
          expect(updates.last.entriesTotal, 3);
          expect(
            updates.any(
              (update) =>
                  update.bytesDone > 0 && update.bytesDone < data.length,
            ),
            isTrue,
          );
          expect(
            updates.map((v) => v.bytesDone),
            orderedEquals(updates.map((v) => v.bytesDone).toList()..sort()),
          );
        }
        expect(
          await root
              .list()
              .where(
                (item) => p.basename(item.path).startsWith('.sidecar-zip-'),
              )
              .isEmpty,
          isTrue,
        );
      },
    );
  }

  test(
    'accepts a conventional ZIP generated independently, with stored/deflated members',
    () async {
      final stored = ArchiveFile('stored', 4, ascii.encode('file'))
        ..compression = CompressionType.none;
      final compressed = ArchiveFile.string('dir/deflate', 'contents');
      final archive = Archive()
        ..add(stored)
        ..add(compressed);
      final bytes = ZipEncoder().encode(archive);
      await File(p.join(root.path, 'standard.zip')).writeAsBytes(bytes);
      await extract('standard.zip');
      expect(await File(p.join(stage.path, 'stored')).readAsString(), 'file');
      expect(
        await File(p.join(stage.path, 'dir', 'deflate')).readAsString(),
        'contents',
      );
    },
  );

  test('accepts conventional TAR root directory and GNU long name', () async {
    final filename = List.filled(110, 'a').join();
    final sink = _BytesSink();
    final encoder = tarConverterWith(
      format: OutputFormat.gnuLongName,
    ).startChunkedConversion(sink);
    encoder.add(tarEntry('./', [], type: TypeFlag.dir));
    encoder.add(tarEntry('./nested/$filename', [3, 4]));
    encoder.close();
    await File(
      p.join(root.path, 'standard.tar'),
    ).writeAsBytes(sink.builder.takeBytes());
    await extract('standard.tar');
    expect(await File(p.join(stage.path, 'nested', filename)).readAsBytes(), [
      3,
      4,
    ]);
  });

  test('rejects unsafe TAR members without writing outside staging', () async {
    for (final name in [
      '../outside',
      '/outside',
      r'C:\outside',
      'one/../outside',
    ]) {
      await writeTar('invalid.tar', [
        tarEntry(name, [1]),
      ]);
      await expectLater(extract('invalid.tar'), failure('archive_unsafe'));
    }
    for (final type in [
      TypeFlag.link,
      TypeFlag.char,
      TypeFlag.fifo,
      TypeFlag.gnuSparse,
    ]) {
      await writeTar('invalid.tar', [
        tarEntry('unsafe', [], type: type, link: 'other'),
      ]);
      await expectLater(extract('invalid.tar'), failure('archive_unsafe'));
    }
    expect(await stage.list().isEmpty, isTrue);
    expect(await File(p.join(root.path, 'outside')).exists(), isFalse);
  });

  test(
    'restores a relative TAR symlink to an internal file declared later',
    () async {
      await writeTar('links.tar', [
        tarEntry(
          'app/bin/tool',
          [],
          type: TypeFlag.symlink,
          link: '../payload/tool',
        ),
        tarEntry('app/payload/tool', [1, 2, 3]),
      ]);
      await extract('links.tar');
      final link = Link(p.join(stage.path, 'app', 'bin', 'tool'));
      expect(await link.target(), '../payload/tool');
      expect(await File(link.path).readAsBytes(), [1, 2, 3]);
    },
  );

  test(
    'declines absolute, escaping, missing and chained TAR link targets',
    () async {
      for (final target in [
        '/outside',
        '../../outside',
        'missing',
        'other-link/value',
      ]) {
        await writeTar('links.tar', [
          tarEntry('app/link', [], type: TypeFlag.symlink, link: target),
          tarEntry('app/other-link', [], type: TypeFlag.symlink, link: 'real'),
          tarEntry('app/real/value', [4]),
        ]);
        await expectLater(extract('links.tar'), failure('archive_unsafe'));
        expect(await Link(p.join(stage.path, 'app', 'link')).exists(), isFalse);
        expect(
          await Link(p.join(stage.path, 'app', 'other-link')).exists(),
          isFalse,
        );
        final app = Directory(p.join(stage.path, 'app'));
        if (await app.exists()) await app.delete(recursive: true);
      }
    },
  );

  test('a TAR link cannot be a parent of an archived file', () async {
    await writeTar('links.tar', [
      tarEntry('nested/link', [], type: TypeFlag.symlink, link: 'real'),
      tarEntry('nested/link/entry', [1]),
      tarEntry('nested/real/entry', [2]),
    ]);
    await expectLater(extract('links.tar'), failure('archive_unsafe'));
    expect(await Link(p.join(stage.path, 'nested', 'link')).exists(), isFalse);
  });

  test('rejects a ZIP link whose target is missing', () async {
    final member = ArchiveFile.string('link', 'target')..mode = 0xa1ff;
    await File(
      p.join(root.path, 'link.zip'),
    ).writeAsBytes(ZipEncoder().encode(Archive()..add(member)));
    await expectLater(extract('link.zip'), failure('archive_unsafe'));
    expect(await stage.list().isEmpty, isTrue);
  });

  test(
    'rejects an existing staging symlink and a symlink source',
    () async {
      final actual = await Directory(p.join(root.path, 'actual')).create();
      final symlink = await Link(
        p.join(stage.path, 'alias'),
      ).create(actual.path);
      await writeTar('blocked.tar', [
        tarEntry('alias/path', [1]),
      ]);
      await expectLater(extract('blocked.tar'), failure('archive_unsafe'));
      await expectLater(
        create('blocked.zip', [entry(symlink, 'source', 1)]),
        failure('archive_unsafe'),
      );
      expect(await actual.list().isEmpty, isTrue);
    },
    skip: Platform.isWindows,
  );

  test('rejects duplicate normalized destinations', () async {
    await writeTar('duplicate.tar', [
      tarEntry('file', [1]),
      tarEntry('./file', [2]),
    ]);
    await expectLater(extract('duplicate.tar'), failure('archive_unsafe'));
    expect(await File(p.join(stage.path, 'file')).readAsBytes(), [1]);
  });

  test(
    'enforces declared byte limits before reading or writing the member',
    () async {
      final file = await File(p.join(root.path, 'empty')).create();
      await expectLater(
        create('large.zip', [entry(file, 'f', 100 * 1024 * 1024 * 1024)]),
        failure('archive_limit'),
      );
      expect(await File(p.join(root.path, 'large.zip')).exists(), isFalse);
      await expectLater(
        create('changed.zip', [entry(file, 'f', 1)]),
        failure('archive_invalid'),
      );
    },
  );

  test(
    'refuses to create an archive outside its caller staging root',
    () async {
      final outside = File(p.join(root.path, 'outside.zip'));
      await expectLater(
        createSidecarArchive(
          entries: [],
          archivePath: outside.path,
          formatPath: outside.path,
          staging: stage,
          cancellation: SidecarCancellation(),
          onProgress: (_) {},
        ),
        failure('archive_unsafe'),
      );
      expect(await outside.exists(), isFalse);
    },
  );

  test('rejects changed ZIP payload with valid archive framing', () async {
    final member = ArchiveFile.string('file', 'original')
      ..compression = CompressionType.none;
    final bytes = Uint8List.fromList(
      ZipEncoder().encode(Archive()..add(member)),
    );
    final metadata = ByteData.sublistView(bytes);
    final dataOffset =
        30 +
        metadata.getUint16(26, Endian.little) +
        metadata.getUint16(28, Endian.little);
    bytes[dataOffset] ^= 1;
    await File(p.join(root.path, 'corrupt.zip')).writeAsBytes(bytes);
    await expectLater(extract('corrupt.zip'), failure('archive_invalid'));
  });

  test('rejects malformed/truncated archives', () async {
    await writeTar('short.tgz', [tarEntry('file', ascii.encode('contents'))]);
    final gzipFile = File(p.join(root.path, 'short.tgz'));
    final bytes = await gzipFile.readAsBytes();
    await gzipFile.writeAsBytes(bytes.sublist(0, bytes.length - 8));
    await expectLater(extract('short.tgz'), failure('archive_invalid'));
    await File(
      p.join(root.path, 'broken.zip'),
    ).writeAsString('not a ZIP archive');
    await expectLater(extract('broken.zip'), failure('archive_invalid'));
  });

  for (final format in ['cancel.zip', 'cancel.tgz']) {
    test('cancels during creation and extraction: $format', () async {
      final input = await File(
        p.join(root.path, 'source'),
      ).writeAsBytes(Uint8List(512 * 1024));
      final entries = [entry(input, 'input', await input.length())];
      final createCancellation = SidecarCancellation();
      await expectLater(
        create(
          format,
          entries,
          cancellation: createCancellation,
          progress: (v) {
            if (v.bytesDone > 0) createCancellation.cancel();
          },
        ),
        throwsA(isA<SidecarCancelled>()),
      );
      expect(
        await root
            .list()
            .where((item) => p.basename(item.path).startsWith('.sidecar-zip-'))
            .isEmpty,
        isTrue,
      );
      await File(p.join(root.path, format)).delete();
      await create(format, entries);
      final extractCancellation = SidecarCancellation();
      await expectLater(
        extract(
          format,
          cancellation: extractCancellation,
          progress: (v) {
            if (v.bytesDone > 0) extractCancellation.cancel();
          },
        ),
        throwsA(isA<SidecarCancelled>()),
      );
    });
  }
}

final class _BytesSink implements Sink<List<int>> {
  final builder = BytesBuilder(copy: false);
  @override
  void add(List<int> data) => builder.add(data);
  @override
  void close() {}
}
