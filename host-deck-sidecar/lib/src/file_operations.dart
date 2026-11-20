import 'dart:io';

import 'package:host_deck_sidecar/protocol.dart';
import 'package:path/path.dart' as p;

import 'archive_operations.dart';
import 'file_system.dart';

const _payloadName = 'payload';

Future<void> runFileOperation({
  required SidecarOperation operation,
  required String sourcePath,
  required String targetPath,
  required SidecarCancellation cancellation,
  required void Function(SidecarProgress) onProgress,
}) async {
  cancellation.throwIfCancelled();
  try {
    final fs = LinuxFileSystem();
    final source = fs.locate(sourcePath);
    try {
      final target = fs.locate(targetPath);
      try {
        await _FileOperation(
          fs,
          source,
          target,
          cancellation,
          onProgress,
        ).run(operation, sourcePath, targetPath);
      } finally {
        target.parent.close();
      }
    } finally {
      source.parent.close();
    }
  } on FileSystemException catch (e) {
    throw SidecarException('io_error', e.toString());
  }
}

final class _Entry {
  final String name;
  final FileSnapshot snapshot;
  String? linkTarget;
  final children = <_Entry>[];

  _Entry(this.name, this.snapshot);
}

final class _FileOperation {
  final LinuxFileSystem fs;
  final FileLocation source;
  final FileLocation target;
  final SidecarCancellation cancellation;
  final void Function(SidecarProgress) onProgress;
  int _totalBytes = 0;
  int _totalEntries = 0;
  int _bytesDone = 0;
  int _entriesDone = 0;
  final Stopwatch _progressClock = Stopwatch()..start();
  int _lastEmission = 0;
  int _workUnits = 0;

  _FileOperation(
    this.fs,
    this.source,
    this.target,
    this.cancellation,
    this.onProgress,
  );

  Future<void> run(
    SidecarOperation operation,
    String sourcePath,
    String targetPath,
  ) async {
    final initial = fs.statAt(source.parent, source.name);
    if (initial == null) {
      throw SidecarException('not_found', 'Source does not exist: $sourcePath');
    }
    final allowSymlinks = operation == SidecarOperation.compress;
    _requireSupported(initial, sourcePath, allowSymlinks: allowSymlinks);
    if (operation == SidecarOperation.extract && !initial.isFile) {
      throw const SidecarException(
        'unsupported_type',
        'The archive source must be a regular file.',
      );
    }
    _checkTarget(initial);
    _emit(SidecarPhase.scanning, force: true);
    await _checkpoint(alwaysYield: true);
    final tree = await _scan(
      source.parent,
      source.name,
      initial,
      {},
      allowSymlinks: allowSymlinks,
    );
    _emit(SidecarPhase.scanning, force: true, totals: true);

    if (operation == SidecarOperation.move) {
      _boundary();
      await _prepareCommit(sourcePath, targetPath, tree, reportTotals: false);
      try {
        _rename(source.parent, source.name, target.parent, target.name);
        return;
      } on FileSystemException catch (e) {
        if (e.osError?.errorCode != errnoCrossDevice) rethrow;
      }
    }

    final stage = fs.createStaging(target.parent);
    try {
      switch (operation) {
        case SidecarOperation.copy:
        case SidecarOperation.move:
          _emit(SidecarPhase.working, force: true, totals: true);
          await _copy(
            source.parent,
            tree,
            stage.directory,
            _payloadName,
            metadata: true,
          );
          _emit(SidecarPhase.working, force: true, totals: true);
        case SidecarOperation.compress:
        case SidecarOperation.extract:
          await _archive(operation, stage, tree, targetPath);
      }
      // Don't publish an inconsistent source tree, even when its root inode and
      // directory timestamps remained stable during a file content edit.
      await _prepareCommit(sourcePath, targetPath, tree);
      _rename(stage.directory, _payloadName, target.parent, target.name);
      if (operation == SidecarOperation.move) {
        await _removeSource(sourcePath, tree);
      }
    } finally {
      await fs.cleanStaging(stage);
    }
  }

  void _checkTarget(FileSnapshot root) {
    final existing = fs.statAt(target.parent, target.name);
    if ((existing?.sameIdentity(root) ?? false) ||
        (root.isDirectory && target.ancestors.any(root.sameIdentity))) {
      throw const SidecarException(
        'invalid_target',
        'Target is the source or is inside the source directory.',
      );
    }
    if (existing != null) {
      if (existing.isSymlink || (!existing.isFile && !existing.isDirectory)) {
        _requireSupported(existing, target.name);
      }
      throw const SidecarException(
        'target_exists',
        'The target already exists.',
      );
    }
  }

  void _requireSupported(
    FileSnapshot snapshot,
    String name, {
    bool allowSymlinks = false,
  }) {
    if (!snapshot.isDirectory &&
        !snapshot.isFile &&
        !(allowSymlinks && snapshot.isSymlink)) {
      throw SidecarException(
        'unsupported_type',
        'Symbolic links and special files are not supported: $name',
      );
    }
  }

  Never _changed(String name) => throw SidecarException(
    'source_changed',
    'The source changed during the operation: $name',
  );

  FileSnapshot _expect(
    FileSnapshot? found,
    FileSnapshot expected,
    String name, {
    bool checkCtime = true,
  }) {
    if (found == null || !expected.unchanged(found, checkCtime: checkCtime)) {
      _changed(name);
    }
    return found;
  }

  FileHandle _pin(FileHandle parent, _Entry entry, {FileSnapshot? expected}) {
    final FileHandle handle;
    try {
      handle = fs.openPath(parent, entry.name);
    } on FileSystemException catch (e) {
      if (e.osError?.errorCode == errnoNoEntry) _changed(entry.name);
      rethrow;
    }
    try {
      _expect(handle.snapshot, expected ?? entry.snapshot, entry.name);
      return handle;
    } catch (_) {
      handle.close();
      rethrow;
    }
  }

  String _readLink(FileHandle parent, FileHandle pinned, _Entry entry) {
    final name = entry.name;
    final snapshot = entry.snapshot;
    _expect(fs.statAt(parent, name), snapshot, name);
    try {
      final value = fs.readLinkAt(parent, name);
      // The pinned descriptor still refers to the original symlink even if the
      // name was swapped while readlinkat ran. Never inspect the referent.
      if (fs.readLinkAt(pinned, '') != value) _changed(name);
      return value;
    } finally {
      _expect(pinned.snapshot, snapshot, name);
      _expect(fs.statAt(parent, name), snapshot, name);
    }
  }

  void _verifyLink(FileHandle parent, FileHandle pinned, _Entry entry) {
    if (_readLink(parent, pinned, entry) != entry.linkTarget) {
      _changed(entry.name);
    }
  }

  Future<_Entry> _scan(
    FileHandle parent,
    String name,
    FileSnapshot snapshot,
    Set<(int, int, int)> ancestors, {
    required bool allowSymlinks,
  }) async {
    await _checkpoint();
    _requireSupported(snapshot, name, allowSymlinks: allowSymlinks);
    final entry = _Entry(name, snapshot);
    final pinned = _pin(parent, entry);
    try {
      _totalEntries++;
      if (snapshot.isFile) _totalBytes += snapshot.size;
      _emit(SidecarPhase.scanning, scanning: true);
      if (snapshot.isSymlink) {
        entry.linkTarget = _readLink(parent, pinned, entry);
      } else if (snapshot.isDirectory) {
        final id = (snapshot.deviceMajor, snapshot.deviceMinor, snapshot.inode);
        if (!ancestors.add(id)) {
          throw const SidecarException(
            'unsupported_type',
            'Directory mount cycle in the source.',
          );
        }
        try {
          await fs.forEachName(pinned, (childName) async {
            final child = fs.statAt(pinned, childName) ?? _changed(childName);
            entry.children.add(
              await _scan(
                pinned,
                childName,
                child,
                ancestors,
                allowSymlinks: allowSymlinks,
              ),
            );
          });
        } finally {
          ancestors.remove(id);
        }
      }
      _expect(pinned.snapshot, snapshot, name);
      _expect(fs.statAt(parent, name), snapshot, name);
      return entry;
    } finally {
      pinned.close();
    }
  }

  Future<void> _copy(
    FileHandle sourceParent,
    _Entry entry,
    FileHandle targetParent,
    String targetName, {
    required bool metadata,
    void Function(_Entry entry, String relativePath)? trackArchive,
    String? relativePath,
  }) async {
    await _checkpoint();
    final pinned = _pin(sourceParent, entry);
    try {
      if (entry.snapshot.isSymlink) {
        // The snapshot contains no filesystem entry for a symlink. Only the
        // compression writer gets its target, as archive metadata.
        if (metadata || relativePath == null || trackArchive == null) {
          _requireSupported(entry.snapshot, entry.name);
        }
        _verifyLink(sourceParent, pinned, entry);
        trackArchive!(entry, relativePath!);
        return;
      }
      if (relativePath != null) trackArchive?.call(entry, relativePath);
      if (entry.snapshot.isDirectory) {
        final output = fs.newDirectory(targetParent, targetName);
        try {
          for (final child in entry.children) {
            await _copy(
              pinned,
              child,
              output,
              child.name,
              metadata: metadata,
              trackArchive: trackArchive,
              relativePath: relativePath == null
                  ? null
                  : '$relativePath/${child.name}',
            );
          }
          if (metadata) fs.applyMetadata(output, entry.snapshot);
        } finally {
          output.close();
        }
      } else {
        final input = fs.openRegular(pinned);
        try {
          final output = fs.newFile(targetParent, targetName);
          try {
            await fs.copyBytes(input, output, entry.snapshot.size, (
              bytes,
            ) async {
              if (metadata) {
                _bytesDone += bytes;
                _emit(SidecarPhase.working, totals: true);
              }
              await _checkpoint();
            });
            if (metadata) {
              fs.applyMetadata(output, entry.snapshot);
            } else {
              fs.ensurePrivateFile(output);
            }
          } finally {
            output.close();
          }
        } finally {
          input.close();
        }
      }
      _expect(pinned.snapshot, entry.snapshot, entry.name);
      _expect(fs.statAt(sourceParent, entry.name), entry.snapshot, entry.name);
      if (metadata) {
        _entriesDone++;
        _emit(SidecarPhase.working, totals: true);
      }
    } finally {
      pinned.close();
    }
  }

  Future<void> _archive(
    SidecarOperation operation,
    FileStaging stage,
    _Entry tree,
    String targetPath,
  ) async {
    final snapshot = fs.newDirectory(stage.directory, 'input');
    try {
      final compress = operation == SidecarOperation.compress;
      final entries = <ArchiveSourceEntry>[];
      // Stage a stable read of the source before measuring archive payload I/O.
      _emit(SidecarPhase.scanning, force: true, totals: true);
      await _copy(
        source.parent,
        tree,
        snapshot,
        tree.name,
        metadata: false,
        relativePath: compress ? tree.name : null,
        trackArchive: compress
            ? (entry, name) => entries.add(
                ArchiveSourceEntry(
                  path: p.join(snapshot.procPath, name),
                  name: name,
                  isDirectory: entry.snapshot.isDirectory,
                  size: entry.snapshot.isFile ? entry.snapshot.size : 0,
                  mode: entry.snapshot.permissions,
                  modified: entry.snapshot.modified,
                  linkTarget: entry.linkTarget,
                ),
              )
            : null,
      );
      cancellation.throwIfCancelled();
      if (compress) {
        // Archive code requires a real directory as the final component.
        // Its parent is still the procfs reference to our pinned stage.
        const outputName = 'archive';
        final output = fs.newDirectory(stage.directory, outputName);
        try {
          final outputPath = p.join(stage.directory.procPath, outputName);
          await createSidecarArchive(
            entries: entries,
            archivePath: p.join(outputPath, _payloadName),
            formatPath: targetPath,
            staging: Directory(outputPath),
            cancellation: cancellation,
            onProgress: _archiveProgress,
          );
          fs.renameNoReplace(
            output,
            _payloadName,
            stage.directory,
            _payloadName,
          );
        } finally {
          output.close();
        }
      } else {
        final payload = fs.newDirectory(stage.directory, _payloadName);
        try {
          await extractSidecarArchive(
            archivePath: p.join(snapshot.procPath, tree.name),
            staging: Directory(p.join(stage.directory.procPath, _payloadName)),
            cancellation: cancellation,
            onProgress: _archiveProgress,
          );
        } finally {
          payload.close();
        }
      }
    } finally {
      snapshot.close();
    }
  }

  void _archiveProgress(SidecarProgress progress) {
    _bytesDone = progress.bytesDone;
    _entriesDone = progress.entriesDone;
    _totalBytes = progress.bytesTotal ?? progress.bytesDone;
    _totalEntries = progress.entriesTotal ?? progress.entriesDone;
    onProgress(progress);
  }

  Future<void> _verify(
    FileHandle parent,
    _Entry entry, {
    bool removing = false,
    FileSnapshot? mount,
  }) async {
    await _checkpoint(cancellable: !removing);
    final actualName = entry.name;
    final pinned = _pin(parent, entry);
    try {
      if (mount != null && !entry.snapshot.sameMount(mount)) {
        throw const SidecarException(
          'source_changed',
          'Refusing to remove a source tree containing another mount.',
        );
      }
      if (entry.snapshot.isDirectory) {
        final rootMount = removing ? mount ?? entry.snapshot : null;
        final actual = <String>{};
        await fs.forEachName(pinned, (childName) async {
          await _checkpoint(cancellable: !removing);
          actual.add(childName);
        });
        if (actual.length != entry.children.length) _changed(actualName);
        for (final child in entry.children) {
          if (!actual.remove(child.name)) _changed(child.name);
          await _verify(pinned, child, removing: removing, mount: rootMount);
        }
      } else if (entry.snapshot.isSymlink) {
        _verifyLink(parent, pinned, entry);
      }
      _expect(pinned.snapshot, entry.snapshot, actualName);
      _expect(fs.statAt(parent, actualName), entry.snapshot, actualName);
    } finally {
      pinned.close();
    }
  }

  Future<void> _prepareCommit(
    String sourcePath,
    String targetPath,
    _Entry tree, {
    bool reportTotals = true,
  }) async {
    _emit(SidecarPhase.committing, force: true, totals: reportTotals);
    await _checkpoint(alwaysYield: true);
    await _verify(source.parent, tree);
    _verifyParent(sourcePath, source);
    _verifyParent(targetPath, target, targetParent: true);
    _expect(fs.statAt(source.parent, tree.name), tree.snapshot, tree.name);
  }

  void _verifyParent(
    String path,
    FileLocation original, {
    bool targetParent = false,
  }) {
    final current = fs.locate(path);
    try {
      final former = original.parent.snapshot;
      final now = current.parent.snapshot;
      if (current.name != original.name ||
          !former.sameIdentity(now) ||
          former.mountId != now.mountId ||
          original.ancestors.length != current.ancestors.length ||
          List.generate(current.ancestors.length, (i) => i).any(
            (i) => !current.ancestors[i].sameIdentity(original.ancestors[i]),
          )) {
        if (targetParent) {
          throw const SidecarException(
            'invalid_target',
            'The target parent changed during the operation.',
          );
        }
        _changed(path);
      }
    } finally {
      current.parent.close();
    }
  }

  void _rename(FileHandle from, String name, FileHandle to, String targetName) {
    try {
      fs.renameNoReplace(from, name, to, targetName);
    } on FileSystemException catch (e) {
      if (e.osError?.errorCode == errnoExists) {
        throw const SidecarException(
          'target_exists',
          'The target already exists.',
        );
      }
      rethrow;
    }
  }

  Future<void> _removeSource(String sourcePath, _Entry tree) async {
    _emit(SidecarPhase.removingSource, force: true, totals: true);
    // The destination is already committed. From this point forward failures
    // are reported distinctly so clients don't retry over the published copy.
    FileStaging? quarantine;
    var quarantined = false;
    try {
      await Future<void>.delayed(Duration.zero);
      if (cancellation.isCancelled) {
        throw const SidecarException(
          'cancelled_after_commit',
          'The target was copied; the source was not removed.',
        );
      }
      _verifyParent(sourcePath, source);
      await _verify(source.parent, tree, removing: true);
      if (cancellation.isCancelled) {
        throw const SidecarException(
          'cancelled_after_commit',
          'The target was copied; the source was not removed.',
        );
      }
      _verifyParent(sourcePath, source);
      quarantine = fs.createStaging(source.parent);
      _expect(
        fs.statAt(source.parent, source.name),
        tree.snapshot,
        source.name,
      );
      // Detach the source root atomically before inspecting or unlinking it.
      // If the user swapped the source path, validate the moved object and put
      // it back (never replace a new entry that meanwhile appeared there).
      fs.renameNoReplace(
        source.parent,
        source.name,
        quarantine.directory,
        _payloadName,
      );
      quarantined = true;
      final movedRoot = _expect(
        fs.statAt(quarantine.directory, _payloadName),
        tree.snapshot,
        _payloadName,
        checkCtime: false, // The rename changes the root inode's ctime.
      );
      final movedTree = _Entry(_payloadName, movedRoot)
        ..children.addAll(tree.children);
      await _verify(quarantine.directory, movedTree, removing: true);
      if (cancellation.isCancelled) {
        throw const SidecarException(
          'cancelled_after_commit',
          'The target was copied; the source was not removed.',
        );
      }
      await _delete(quarantine.directory, movedTree, touched: {});
      quarantined = false;
    } catch (e) {
      if (quarantined) {
        try {
          fs.renameNoReplace(
            quarantine!.directory,
            _payloadName,
            source.parent,
            source.name,
          );
          quarantined = false;
        } on FileSystemException {
          // Leave recovery data in quarantine when restoring would overwrite.
        }
      }
      final recovery = quarantined
          ? ' Remaining source: $sourcePath (recover ${quarantine!.name}/$_payloadName in its parent).'
          : '';
      if (e is SidecarException &&
          e.code == 'cancelled_after_commit' &&
          !quarantined) {
        rethrow;
      }
      throw SidecarException(
        'source_not_removed',
        'The target was committed but the source could not be safely removed. $e$recovery',
      );
    } finally {
      if (quarantine != null) {
        if (quarantined) {
          quarantine.directory.close();
        } else {
          await fs.cleanStaging(quarantine);
        }
      }
    }
  }

  Future<void> _delete(
    FileHandle parent,
    _Entry entry, {
    required Map<(int, int, int), FileSnapshot> touched,
  }) async {
    await _checkpoint(cancellable: false);
    final actualName = entry.name;
    final id = (
      entry.snapshot.deviceMajor,
      entry.snapshot.deviceMinor,
      entry.snapshot.inode,
    );
    // Unlinking one hard link changes ctime on all remaining aliases. Use
    // the refreshed snapshot so a later unrelated ctime change is detected.
    final expected = touched[id] ?? entry.snapshot;
    final pinned = _pin(parent, entry, expected: expected);
    try {
      if (entry.snapshot.isDirectory) {
        for (final child in entry.children) {
          await _delete(pinned, child, touched: touched);
        }
        if (fs.statAt(parent, actualName)?.sameIdentity(entry.snapshot) !=
            true) {
          _changed(actualName);
        }
      } else {
        _expect(fs.statAt(parent, actualName), expected, actualName);
      }
      fs.unlink(parent, actualName, directory: entry.snapshot.isDirectory);
      if (entry.snapshot.isFile) {
        touched[id] = _expect(
          pinned.snapshot,
          entry.snapshot,
          actualName,
          checkCtime: false,
        );
      }
    } finally {
      pinned.close();
    }
  }

  void _boundary() => cancellation.throwIfCancelled();

  Future<void> _checkpoint({
    bool cancellable = true,
    bool alwaysYield = false,
  }) async {
    if (cancellable) _boundary();
    if (alwaysYield || ++_workUnits % 16 == 0) {
      await Future<void>.delayed(Duration.zero);
      if (cancellable) _boundary();
    }
  }

  void _emit(
    SidecarPhase phase, {
    bool force = false,
    bool totals = false,
    bool scanning = false,
  }) {
    final now = _progressClock.elapsedMilliseconds;
    if (!force && now - _lastEmission < 50) return;
    _lastEmission = now;
    final scan = phase == SidecarPhase.scanning;
    onProgress(
      SidecarProgress(
        phase: phase,
        bytesDone: scan && (scanning || totals) ? _totalBytes : _bytesDone,
        bytesTotal: totals ? _totalBytes : null,
        entriesDone: scan && (scanning || totals)
            ? _totalEntries
            : _entriesDone,
        entriesTotal: totals ? _totalEntries : null,
      ),
    );
  }
}
