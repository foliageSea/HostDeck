@TestOn('linux')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart' show ZipDecoder;
import 'package:host_deck_sidecar/protocol.dart';
import 'package:host_deck_sidecar/src/file_operations.dart';
import 'package:host_deck_sidecar/src/file_system.dart';
import 'package:path/path.dart' as p;
import 'package:tar/tar.dart';
import 'package:test/test.dart';

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('hostdeck-sidecar-test-');
  });

  tearDown(() async {
    await temp.delete(recursive: true);
  });

  String at(String name) => p.join(temp.path, name);

  Future<void> operation(
    SidecarOperation operation,
    String source,
    String destination, {
    SidecarCancellation? cancellation,
    void Function(SidecarProgress)? onProgress,
  }) => runFileOperation(
    operation: operation,
    sourcePath: source,
    targetPath: destination,
    cancellation: cancellation ?? SidecarCancellation(),
    onProgress: onProgress ?? (_) {},
  );

  Matcher error(String code) =>
      isA<SidecarException>().having((e) => e.code, 'code', code);

  FileSnapshot snapshot(String path) {
    final fs = LinuxFileSystem();
    final endpoint = fs.locate(path);
    try {
      return fs.statAt(endpoint.parent, endpoint.name)!;
    } finally {
      endpoint.parent.close();
    }
  }

  void checkNoStaging(Directory directory) {
    expect(
      directory.listSync().where(
        (entry) => p.basename(entry.path).startsWith('.hostdeck-sidecar-'),
      ),
      isEmpty,
    );
  }

  Future<void> command(String executable, List<String> args) async {
    final result = await Process.run(executable, args);
    expect(result.exitCode, 0, reason: '$executable $args: ${result.stderr}');
  }

  test(
    'copies directory tree with modes/mtime, strips special bits, and reports progress',
    () async {
      final source = await Directory(at('source')).create();
      final nested = await Directory(p.join(source.path, 'nested')).create();
      final file = await File(
        p.join(nested.path, '﻿named'),
      ).writeAsString('hello');
      await Directory(p.join(source.path, 'empty')).create();
      final modified = DateTime.utc(2011, 12, 13, 14, 15, 16);
      await command('chmod', ['4751', file.path]);
      await command('chmod', ['1750', nested.path]);
      await command('touch', [
        '-m',
        '-d',
        '2011-12-13 14:15:16.123456789 UTC',
        nested.path,
        source.path,
      ]);
      await file.setLastModified(modified);
      final progress = <SidecarProgress>[];

      await operation(
        SidecarOperation.copy,
        source.path,
        at('destination'),
        onProgress: progress.add,
      );
      final child = File(at('destination/nested/﻿named'));
      expect(await child.readAsString(), 'hello');
      expect(await Directory(at('destination/empty')).exists(), isTrue);
      expect(await file.exists(), isTrue);
      expect(snapshot(child.path).mode & 0xfff, 0x1e9); // 0751
      final copiedDir = snapshot(at('destination/nested'));
      expect(copiedDir.mode & 0xfff, 0x1e8); // 0750
      expect(copiedDir.mtimeNanoseconds, 123456789);
      expect(copiedDir.mtimeSeconds, snapshot(nested.path).mtimeSeconds);
      expect((await child.lastModified()).toUtc(), modified);
      expect(progress.first.phase, SidecarPhase.scanning);
      expect(progress.last.phase, SidecarPhase.committing);
      final working = progress
          .where((item) => item.phase == SidecarPhase.working)
          .last;
      expect(working.bytesDone, 5);
      expect(working.bytesTotal, 5);
      expect(working.entriesDone, 4);
      expect(working.entriesTotal, 4);
      checkNoStaging(temp);
    },
  );

  test('native move keeps inode and source on a target collision', () async {
    final source = await File(at('source')).writeAsString('source data');
    final identity = snapshot(source.path);
    final phases = <SidecarPhase>[];
    await operation(
      SidecarOperation.move,
      source.path,
      at('target'),
      onProgress: (progress) {
        phases.add(progress.phase);
      },
    );
    expect(await source.exists(), isFalse);
    expect(await File(at('target')).readAsString(), 'source data');
    expect(identity.sameIdentity(snapshot(at('target'))), isTrue);
    expect(phases, isNot(contains(SidecarPhase.removingSource)));
    await source.writeAsString('new source');
    await expectLater(
      operation(SidecarOperation.move, source.path, at('target')),
      throwsA(error('target_exists')),
    );
    expect(await source.readAsString(), 'new source');
    expect(await File(at('target')).readAsString(), 'source data');
    checkNoStaging(temp);
  });

  for (final kind in [SidecarOperation.copy, SidecarOperation.move]) {
    test('$kind never replaces a racing target at commit', () async {
      final source = await File(at('source')).writeAsString('source data');
      final target = File(at('target'));
      await expectLater(
        operation(
          kind,
          source.path,
          target.path,
          onProgress: (progress) {
            if (progress.phase == SidecarPhase.committing) {
              target.writeAsStringSync('racing data');
            }
          },
        ),
        throwsA(error('target_exists')),
      );
      expect(await source.readAsString(), 'source data');
      expect(await target.readAsString(), 'racing data');
      checkNoStaging(temp);
    });
  }

  test(
    'refuses the source, hardlink alias, or a path under the source directory',
    () async {
      final directory = await Directory(at('source')).create();
      final source = await File(at('source/file')).writeAsString('source data');
      final hardlink = at('alias');
      await command('ln', [source.path, hardlink]);
      await expectLater(
        operation(SidecarOperation.copy, source.path, source.path),
        throwsA(error('invalid_target')),
      );
      await expectLater(
        operation(SidecarOperation.copy, source.path, hardlink),
        throwsA(error('invalid_target')),
      );
      await expectLater(
        operation(SidecarOperation.copy, directory.path, at('source/target')),
        throwsA(error('invalid_target')),
      );
      expect(await File(at('source/target')).exists(), isFalse);
      checkNoStaging(temp);
    },
  );

  test(
    'rejects links and special files before opening or mutating them',
    () async {
      final directory = await Directory(at('source')).create();
      final actual = await File(at('actual')).writeAsString('actual contents');
      final link = await Link(at('source/link')).create(actual.path);
      await expectLater(
        operation(SidecarOperation.copy, link.path, at('target')),
        throwsA(error('unsupported_type')),
      );
      await expectLater(
        operation(SidecarOperation.move, directory.path, at('target')),
        throwsA(error('unsupported_type')),
      );
      await expectLater(
        operation(SidecarOperation.extract, link.path, at('target')),
        throwsA(error('unsupported_type')),
      );
      await link.delete();
      await command('mkfifo', [at('source/fifo')]);
      await expectLater(
        operation(SidecarOperation.compress, directory.path, at('target.zip')),
        throwsA(error('unsupported_type')),
      );
      expect(await File(at('target.zip')).exists(), isFalse);
      await expectLater(
        operation(SidecarOperation.copy, directory.path, at('target')),
        throwsA(error('unsupported_type')),
      );
      await Link(at('source-dir-link')).create(directory.path);
      await expectLater(
        operation(
          SidecarOperation.copy,
          actual.path,
          at('source-dir-link/target'),
        ),
        throwsA(error('unsupported_type')),
      );
      await Link(at('target')).create(actual.path);
      await expectLater(
        operation(SidecarOperation.copy, actual.path, at('target')),
        throwsA(error('unsupported_type')),
      );
      expect(await actual.readAsString(), 'actual contents');
      checkNoStaging(temp);
    },
  );

  for (final phase in [
    SidecarPhase.scanning,
    SidecarPhase.working,
    SidecarPhase.committing,
  ]) {
    test(
      'cancellation during ${phase.name} leaves no target or staging',
      () async {
        final source = await File(
          at('source'),
        ).writeAsBytes(Uint8List(2 * 1024 * 1024));
        final cancellation = SidecarCancellation();
        await expectLater(
          operation(
            SidecarOperation.copy,
            source.path,
            at('target'),
            cancellation: cancellation,
            onProgress: (progress) {
              if (progress.phase == phase) cancellation.cancel();
            },
          ),
          throwsA(isA<SidecarCancelled>()),
        );
        expect(await source.exists(), isTrue);
        expect(await File(at('target')).exists(), isFalse);
        checkNoStaging(temp);
      },
    );
  }

  test(
    'does not commit when source file changes without replacing its parent entry',
    () async {
      final directory = await Directory(at('source')).create();
      final file = await File(at('source/file')).writeAsString('source data');
      await expectLater(
        operation(
          SidecarOperation.copy,
          directory.path,
          at('target'),
          onProgress: (progress) {
            if (progress.phase == SidecarPhase.committing) {
              file.writeAsStringSync('EDITED DATA');
            }
          },
        ),
        throwsA(error('source_changed')),
      );
      expect(await file.readAsString(), 'EDITED DATA');
      expect(await Directory(at('target')).exists(), isFalse);
      checkNoStaging(temp);
    },
  );

  Future<Directory?> crossFilesystem() async {
    final Directory target;
    try {
      target = await Directory('/dev/shm').createTemp('hostdeck-sidecar-test-');
    } on FileSystemException {
      return null;
    }
    final src = snapshot(temp.path);
    final dst = snapshot(target.path);
    if (src.deviceMajor == dst.deviceMajor &&
        src.deviceMinor == dst.deviceMinor) {
      await target.delete();
      return null;
    }
    addTearDown(() => target.delete(recursive: true));
    return target;
  }

  test(
    'EXDEV copies, commits, then removes source including internal hardlinks',
    () async {
      final remote = await crossFilesystem();
      if (remote == null) {
        markTestSkipped(
          'Requires writable /dev/shm on a different filesystem.',
        );
        return;
      }
      await Directory(at('source')).create();
      final file = await File(at('source/file')).writeAsString('data');
      await command('ln', [file.path, at('source/second')]);
      final target = p.join(remote.path, 'target');
      final phases = <SidecarPhase>[];
      await operation(
        SidecarOperation.move,
        at('source'),
        target,
        onProgress: (progress) {
          phases.add(progress.phase);
          if (progress.phase == SidecarPhase.working) {
            expect(Directory(target).existsSync(), isFalse);
          }
          if (progress.phase == SidecarPhase.removingSource) {
            expect(Directory(target).existsSync(), isTrue);
            expect(file.existsSync(), isTrue);
          }
        },
      );
      expect(
        phases,
        containsAllInOrder([
          SidecarPhase.working,
          SidecarPhase.committing,
          SidecarPhase.removingSource,
        ]),
      );
      expect(Directory(at('source')).existsSync(), isFalse);
      expect(File(p.join(target, 'file')).readAsStringSync(), 'data');
      expect(File(p.join(target, 'second')).readAsStringSync(), 'data');
      checkNoStaging(temp);
      checkNoStaging(remote);
    },
  );

  test(
    'EXDEV cancellation after commit leaves both source and published copy',
    () async {
      final remote = await crossFilesystem();
      if (remote == null) {
        markTestSkipped(
          'Requires writable /dev/shm on a different filesystem.',
        );
        return;
      }
      final source = await File(at('source')).writeAsString('original');
      final target = File(p.join(remote.path, 'target'));
      final cancellation = SidecarCancellation();
      await expectLater(
        operation(
          SidecarOperation.move,
          source.path,
          target.path,
          cancellation: cancellation,
          onProgress: (progress) {
            if (progress.phase == SidecarPhase.removingSource) {
              cancellation.cancel();
            }
          },
        ),
        throwsA(error('cancelled_after_commit')),
      );
      expect(source.readAsStringSync(), 'original');
      expect(target.readAsStringSync(), 'original');
      checkNoStaging(temp);
      checkNoStaging(remote);
    },
  );

  test('EXDEV never removes source if publishing loses a race', () async {
    final remote = await crossFilesystem();
    if (remote == null) {
      markTestSkipped('Requires writable /dev/shm on a different filesystem.');
      return;
    }
    final source = await File(at('source')).writeAsString('original');
    final target = File(p.join(remote.path, 'target'));
    await expectLater(
      operation(
        SidecarOperation.move,
        source.path,
        target.path,
        onProgress: (progress) {
          if (progress.phase == SidecarPhase.working) {
            target.writeAsStringSync('racing target');
          }
          expect(progress.phase, isNot(SidecarPhase.removingSource));
        },
      ),
      throwsA(error('target_exists')),
    );
    expect(source.readAsStringSync(), 'original');
    expect(target.readAsStringSync(), 'racing target');
    checkNoStaging(temp);
    checkNoStaging(remote);
  });

  for (final replaceRoot in [false, true]) {
    test(
      'EXDEV leaves changed source after commit (replace root: $replaceRoot)',
      () async {
        final remote = await crossFilesystem();
        if (remote == null) {
          markTestSkipped(
            'Requires writable /dev/shm on a different filesystem.',
          );
          return;
        }
        final source = await Directory(at('source')).create();
        final file = await File(at('source/file')).writeAsString('original');
        final target = p.join(remote.path, 'target');
        await expectLater(
          operation(
            SidecarOperation.move,
            source.path,
            target,
            onProgress: (progress) {
              if (progress.phase == SidecarPhase.removingSource) {
                if (replaceRoot) {
                  source.renameSync(at('relocated'));
                  source.createSync();
                }
                file.writeAsStringSync('changed!');
              }
            },
          ),
          throwsA(error('source_not_removed')),
        );
        expect(file.readAsStringSync(), 'changed!');
        expect(File(p.join(target, 'file')).readAsStringSync(), 'original');
        if (replaceRoot) {
          expect(File(at('relocated/file')).readAsStringSync(), 'original');
        }
        checkNoStaging(temp);
        checkNoStaging(remote);
      },
    );
  }

  test(
    'compression detects replacement of a top-level symlink at commit',
    () async {
      final link = await Link(at('source')).create('missing-first');
      final target = at('target.tar.gz');
      await expectLater(
        operation(
          SidecarOperation.compress,
          link.path,
          target,
          onProgress: (progress) {
            if (progress.phase == SidecarPhase.committing) {
              link.updateSync('missing-other');
            }
          },
        ),
        throwsA(error('source_changed')),
      );
      expect(await link.target(), 'missing-other');
      expect(await File(target).exists(), isFalse);
      checkNoStaging(temp);
    },
  );

  for (final extension in ['zip', 'tar.gz']) {
    test(
      'compress .$extension records link targets without archiving referents',
      () async {
        final source = await Directory(at('source')).create();
        final outside = await File(
          at('sentinel'),
        ).writeAsString('outside sentinel bytes');
        const regular = 'archive bytes';
        await File(at('source/file')).writeAsString(regular);
        final links = {
          'source/absolute': outside.path,
          'source/relative': '../sentinel',
          'source/dangling': 'missing/目标',
        };
        for (final entry in links.entries) {
          await Link(at(entry.key)).create(entry.value);
        }
        final path = at('archive.$extension');
        var didCheckStage = false;
        await operation(
          SidecarOperation.compress,
          source.path,
          path,
          onProgress: (progress) {
            if (didCheckStage || progress.phase != SidecarPhase.working) return;
            didCheckStage = true;
            final stage = temp.listSync().whereType<Directory>().singleWhere(
              (entry) =>
                  p.basename(entry.path).startsWith('.hostdeck-sidecar-'),
            );
            expect(
              stage
                  .listSync(recursive: true, followLinks: false)
                  .whereType<Link>(),
              isEmpty,
            );
          },
        );
        expect(didCheckStage, isTrue);

        if (extension == 'zip') {
          final zip = ZipDecoder().decodeBytes(await File(path).readAsBytes());
          expect(
            zip.files.map((entry) => entry.name),
            unorderedEquals(['source/', 'source/file', ...links.keys]),
          );
          expect(zip.find('source/file')!.content, utf8.encode(regular));
          for (final entry in links.entries) {
            final archivedLink = zip.find(entry.key)!;
            expect(archivedLink.isSymbolicLink, isTrue);
            expect(archivedLink.symbolicLink, entry.value);
            expect(archivedLink.content, utf8.encode(entry.value));
          }
        } else {
          final tar = TarReader(gzip.decoder.bind(File(path).openRead()));
          final names = <String>[];
          try {
            while (await tar.moveNext()) {
              final entry = tar.current;
              names.add(entry.name);
              final link = links[entry.name];
              if (link != null) {
                expect(entry.type, TypeFlag.symlink);
                expect(entry.header.linkName, link);
                expect(entry.size, 0);
                expect(await entry.contents.isEmpty, isTrue);
              } else if (entry.name == 'source/file') {
                expect(await utf8.decoder.bind(entry.contents).join(), regular);
              }
            }
          } finally {
            await tar.cancel();
          }
          expect(
            names,
            unorderedEquals(['source/', 'source/file', ...links.keys]),
          );
        }
        expect(await outside.readAsString(), 'outside sentinel bytes');
        checkNoStaging(temp);
      },
    );
    test(
      'compress/extract round-trips a safe relative symlink in $extension',
      () async {
        final source = await Directory(at('source')).create();
        final file = await File(
          at('source/file'),
        ).writeAsString('archive bytes');
        await Directory(at('source/nested')).create();
        final link = await Link(at('source/nested/link')).create('../file');
        final archive = at('archive.$extension');
        await operation(SidecarOperation.compress, source.path, archive);
        expect(await File(archive).length(), greaterThan(0));
        expect(await file.readAsString(), 'archive bytes');
        expect(await link.target(), '../file');
        await operation(SidecarOperation.extract, archive, at('target'));
        expect(
          await File(at('target/source/file')).readAsString(),
          'archive bytes',
        );
        final extractedLink = at('target/source/nested/link');
        expect(await Link(extractedLink).target(), '../file');
        expect(await File(extractedLink).readAsString(), 'archive bytes');
        checkNoStaging(temp);
      },
    );
  }
}
