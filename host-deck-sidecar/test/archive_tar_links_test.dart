import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:host_deck_sidecar/protocol.dart';
import 'package:host_deck_sidecar/src/archive_operations.dart';
import 'package:path/path.dart' as p;
import 'package:tar/tar.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;
  late Directory stage;
  late File tarFile;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('sidecar-tar-links-');
    stage = await Directory(p.join(root.path, 'stage')).create();
    tarFile = File(p.join(root.path, 'input.tar'));
  });
  tearDown(() => root.delete(recursive: true));

  Future<void> extract(File archive) => extractSidecarArchive(
    archivePath: archive.path,
    staging: stage,
    cancellation: SidecarCancellation(),
    onProgress: (_) {},
  );

  SynchronousTarEntry tarEntry(
    String name, {
    List<int> data = const [],
    TypeFlag type = TypeFlag.reg,
    String? link,
  }) => TarEntry.data(
    TarHeader(name: name, mode: 0x1a4, typeFlag: type, linkName: link),
    data,
  );

  Future<void> writeTar(
    List<SynchronousTarEntry> entries, {
    OutputFormat format = OutputFormat.pax,
  }) async {
    final bytes = BytesBuilder(copy: false);
    final sink = tarConverterWith(
      format: format,
    ).startChunkedConversion(ByteConversionSink.withCallback(bytes.add));
    for (final entry in entries) {
      sink.add(entry);
    }
    sink.close();
    await tarFile.writeAsBytes(bytes.takeBytes());
  }

  Matcher failure(String code) =>
      throwsA(isA<SidecarException>().having((e) => e.code, 'code', code));

  // Each truncated header field ends in the middle of a UTF-8 sequence.
  final longName = 'bin/${'n' * 94}链';
  final longFile = 'model/${'a' * 89}归';
  final longTarget = '../$longFile';

  for (final format in OutputFormat.values) {
    test(
      'reads long member and link paths from ${format.name}',
      () async {
        await writeTar([
          tarEntry(longName, type: TypeFlag.symlink, link: longTarget),
          tarEntry(longFile, data: [42]),
        ], format: format);
        final path = p.join(stage.path, longName);
        await extract(tarFile);
        expect(await Link(path).target(), longTarget);
        expect(await File(path).readAsBytes(), [42]);
      },
      skip: Platform.isWindows,
    );
  }

  test(
    'writes zero-sized TAR symlink headers with no file bytes',
    () async {
      final input = await Directory(p.join(root.path, 'input')).create();
      final source = await File(
        p.join(input.path, 'program'),
      ).writeAsString('data');
      final sourceLink = await Link(
        p.join(input.path, 'alias'),
      ).create('program');
      final gzipFile = File(p.join(root.path, 'output.tar.gz'));
      const names = ['bin/alias', 'program'];
      final modified = DateTime.utc(2024);
      await createSidecarArchive(
        entries: [
          ArchiveSourceEntry(
            path: sourceLink.path,
            name: names.first,
            isDirectory: false,
            size: 0,
            mode: 0x1ff,
            modified: modified,
            linkTarget: '../program',
          ),
          ArchiveSourceEntry(
            path: source.path,
            name: names.last,
            isDirectory: false,
            size: 4,
            mode: 0x1a4,
            modified: modified,
          ),
        ],
        archivePath: gzipFile.path,
        formatPath: gzipFile.path,
        staging: root,
        cancellation: SidecarCancellation(),
        onProgress: (_) {},
      );
      final reader = TarReader(gzip.decoder.bind(gzipFile.openRead()));
      try {
        expect(await reader.moveNext(), isTrue);
        expect(reader.current.header.typeFlag, TypeFlag.symlink);
        expect(reader.current.header.linkName, '../program');
        expect(reader.current.header.size, 0);
        expect(await reader.current.contents.isEmpty, isTrue);
        expect(await reader.moveNext(), isTrue);
        expect(reader.current.header.name, names.last);
        expect(await reader.moveNext(), isFalse);
      } finally {
        await reader.cancel();
      }
      await extract(gzipFile);
      final alias = p.join(stage.path, names.first);
      expect(await Link(alias).target(), '../program');
      expect(await File(alias).readAsString(), 'data');
    },
    skip: Platform.isWindows,
  );

  test('rejects a symbolic link with a payload', () async {
    await writeTar([
      tarEntry('alias', type: TypeFlag.symlink, link: 'program', data: [42]),
    ]);
    await expectLater(extract(tarFile), failure('archive_invalid'));
    expect(await stage.list().isEmpty, isTrue);
  });

  test('rejects PAX linkpath metadata on non-symlink members', () async {
    await writeTar([
      tarEntry(
        'pax',
        type: TypeFlag.xHeader,
        data: ascii.encode('20 linkpath=program\n'),
      ),
      tarEntry('program', data: [42]),
    ]);
    await expectLater(extract(tarFile), failure('archive_unsafe'));
    expect(await stage.list().isEmpty, isTrue);
  });

  test('rejects dangling GNU long link metadata', () async {
    await writeTar([
      tarEntry(
        '././@LongLink',
        type: TypeFlag.gnuLongLink,
        data: ascii.encode('program'),
      ),
    ]);
    await expectLater(extract(tarFile), failure('archive_invalid'));
    expect(await stage.list().isEmpty, isTrue);
  });
}
