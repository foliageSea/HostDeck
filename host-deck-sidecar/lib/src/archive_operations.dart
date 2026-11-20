import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart' show getCrc32;
import 'package:host_deck_sidecar/protocol.dart';
import 'package:path/path.dart' as p;
import 'package:tar/tar.dart';

part 'archive_zip.dart';
part 'archive_tar.dart';

final class ArchiveSourceEntry {
  final String path;
  final String name;
  final bool isDirectory;
  final int size;
  final int mode;
  final DateTime modified;
  final String? linkTarget;

  const ArchiveSourceEntry({
    required this.path,
    required this.name,
    required this.isDirectory,
    required this.size,
    required this.mode,
    required this.modified,
    this.linkTarget,
  });
}

const _chunkSize = 64 * 1024;
const _maxEntries = 100000;
const _maxPathBytes = 4096;
const _maxPathMetadata = 16 * 1024 * 1024;
const _maxPathDepth = 128;
const _maxFileBytes = 64 * 1024 * 1024 * 1024;
const _maxExpandedBytes = 100 * 1024 * 1024 * 1024;

Never _unsafe(String message) =>
    throw SidecarException('archive_unsafe', message);
Never _invalid(String message) =>
    throw SidecarException('archive_invalid', message);
Never _limit(String message) =>
    throw SidecarException('archive_limit', message);
Never _unsupported() => throw const SidecarException(
  'unsupported_archive',
  'Unsupported archive format.',
);

/// Writes the archive to the caller's staging output; the caller owns cleanup
/// of that output and the final commit. This function owns only its scratch.
Future<void> createSidecarArchive({
  required List<ArchiveSourceEntry> entries,
  required String archivePath,
  required String formatPath,
  required Directory staging,
  required SidecarCancellation cancellation,
  required void Function(SidecarProgress) onProgress,
}) async {
  cancellation.throwIfCancelled();
  final format = formatPath.toLowerCase();
  final zip = format.endsWith('.zip');
  if (!zip && !format.endsWith('.tar.gz') && !format.endsWith('.tgz')) {
    _unsupported();
  }
  final root = await _stageRoot(staging);
  final output = p.normalize(p.absolute(archivePath));
  if (p.dirname(output) != root) _unsafe('Archive output is outside staging.');
  final quota = _ArchiveQuota();
  final names = _ArchiveNames();
  for (final entry in entries) {
    if (quota.entries % 256 == 0) await Future<void>.delayed(Duration.zero);
    cancellation.throwIfCancelled();
    names.add(entry.name, directory: entry.isDirectory);
    final link = entry.linkTarget;
    if (link != null) {
      if (entry.isDirectory || entry.size != 0) {
        _invalid('A symbolic link cannot have a file payload.');
      }
      names.chargeBytes(_linkTargetBytes(link));
    }
    quota.add(entry.isDirectory ? 0 : entry.size);
  }
  await names.validateTree(cancellation);
  final progress = _ArchiveProgress(cancellation, onProgress)
    ..bytesTotal = quota.bytes
    ..entriesTotal = quota.entries
    ..report();
  final file = await _createNewFile(output);
  final writer = await file.open(mode: FileMode.writeOnly);
  try {
    if (zip) {
      await _writeZip(entries, writer, Directory(root), progress);
    } else {
      await _writeTarGzip(entries, writer, progress);
    }
    cancellation.throwIfCancelled();
  } finally {
    await writer.close();
  }
}

/// Extracts files, directories and confined symlinks under private staging.
/// Links are only created after all file data has been checked. The caller
/// owns staging cleanup and commit.
Future<void> extractSidecarArchive({
  required String archivePath,
  required Directory staging,
  required SidecarCancellation cancellation,
  required void Function(SidecarProgress) onProgress,
}) async {
  cancellation.throwIfCancelled();
  final format = archivePath.toLowerCase();
  final zip = format.endsWith('.zip');
  final compressed = format.endsWith('.tar.gz') || format.endsWith('.tgz');
  if (!zip && !compressed && !format.endsWith('.tar')) _unsupported();
  final root = await _stageRoot(staging);
  await _requireType(archivePath, FileSystemEntityType.file);
  final progress = _ArchiveProgress(cancellation, onProgress)..report();
  final target = _ArchiveTarget(root, progress);
  try {
    if (zip) {
      await _extractZip(File(archivePath), target);
    } else {
      await _extractTar(File(archivePath), target, compressed: compressed);
    }
    await target.finishLinks();
    progress.bytesTotal = progress.bytes;
    progress.entriesTotal = progress.entries;
    progress.report();
  } on FormatException catch (_) {
    _invalid('Malformed archive encoding or compressed data.');
  }
}

Future<String> _stageRoot(Directory staging) async {
  final root = p.normalize(p.absolute(staging.path));
  await _requireType(root, FileSystemEntityType.directory);
  return root;
}

Future<void> _requireType(String path, FileSystemEntityType expected) async {
  // The Linux caller may supply an exact, already-open descriptor as the
  // staging root. Do not extend this exception to any member or ordinary link.
  final descriptor =
      Platform.isLinux && RegExp(r'^/proc/self/fd/[0-9]+$').hasMatch(path);
  if (await FileSystemEntity.type(path, followLinks: descriptor) != expected) {
    _unsafe('Unexpected file type: $path');
  }
}

/// POSIX archive names, not host paths. Support common TAR ./ prefixes and
/// trailing directory slashes but never normalize away parent components.
String _entryName(String raw, {required bool directory}) {
  if (raw.length > _maxPathBytes || utf8.encode(raw).length > _maxPathBytes) {
    _limit('Archive entry path is too long.');
  }
  if (raw.startsWith('/') ||
      raw.contains('\\') ||
      raw.contains(':') ||
      raw.contains('\x00')) {
    _unsafe('Archive entry contains an absolute or invalid path.');
  }
  final parts = <String>[];
  for (final name in raw.split('/')) {
    if (name == '..') {
      _unsafe('Archive entry contains a parent path component.');
    }
    if (name == '.' || name.isEmpty) continue;
    // Windows aliases, devices and case-insensitive paths must not land on a
    // different filesystem entry from the one the archive name denotes.
    if (Platform.isWindows &&
        (name.endsWith('.') ||
            name.endsWith(' ') ||
            RegExp(r'[<>"|?*]').hasMatch(name) ||
            RegExp(
              r'^(CON|PRN|AUX|NUL|COM[1-9¹²³]|LPT[1-9¹²³])(?:[. ]|$)',
              caseSensitive: false,
            ).hasMatch(name))) {
      _unsafe('Archive entry contains a reserved Windows path component.');
    }
    if (utf8.encode(name).length > 255) {
      _limit('Archive entry path component is too long.');
    }
    parts.add(name);
    if (parts.length > _maxPathDepth) _limit('Archive entry path is too deep.');
  }
  if (parts.isEmpty && (!directory || !raw.startsWith('.'))) {
    _unsafe('Archive entry has an empty path.');
  }
  if (!directory && raw.endsWith('/')) {
    _unsafe('Archive file has a directory path.');
  }
  return parts.join('/');
}

int _linkTargetBytes(String target) {
  if (target.isEmpty || target.contains(String.fromCharCode(0))) {
    _unsafe('Archive symbolic link has an invalid target.');
  }
  if (target.length > _maxPathBytes) _limit('Archive link target is too long.');
  final size = utf8.encode(target).length;
  if (size > _maxPathBytes) _limit('Archive link target is too long.');
  return size;
}

Future<File> _createNewFile(String path) async {
  if (await FileSystemEntity.type(path, followLinks: false) !=
      FileSystemEntityType.notFound) {
    _unsafe('Archive output collides with an existing path.');
  }
  return File(path).create(exclusive: true);
}

final class _ArchiveQuota {
  int entries = 0;
  int bytes = 0;

  void add(int size) {
    if (size < 0) _invalid('Negative archive entry size.');
    if (++entries > _maxEntries) _limit('Archive contains too many entries.');
    if (size > _maxFileBytes || size > _maxExpandedBytes - bytes) {
      _limit('Archive exceeds the expanded size limit.');
    }
    bytes += size;
  }
}

final class _ArchiveProgress {
  final SidecarCancellation cancellation;
  final void Function(SidecarProgress) onProgress;
  int bytes = 0;
  int entries = 0;
  int? bytesTotal;
  int? entriesTotal;

  _ArchiveProgress(this.cancellation, this.onProgress);

  void report() {
    cancellation.throwIfCancelled();
    onProgress(
      SidecarProgress(
        phase: SidecarPhase.working,
        bytesDone: bytes,
        bytesTotal: bytesTotal,
        entriesDone: entries,
        entriesTotal: entriesTotal,
      ),
    );
    cancellation.throwIfCancelled();
  }

  void advance(int length) {
    bytes += length;
    report();
  }

  void finishEntry() {
    entries++;
    report();
  }
}

Stream<List<int>> _sourceBytes(
  ArchiveSourceEntry entry,
  _ArchiveProgress progress,
) async* {
  final expected = entry.isDirectory
      ? FileSystemEntityType.directory
      : FileSystemEntityType.file;
  await _requireType(entry.path, expected);
  if (entry.isDirectory) return;
  final file = await File(entry.path).open();
  try {
    if (await file.length() != entry.size) {
      _invalid('Archive source size changed after scanning.');
    }
    var remaining = entry.size;
    while (remaining > 0) {
      progress.cancellation.throwIfCancelled();
      final data = await file.read(math.min(_chunkSize, remaining));
      if (data.isEmpty) _invalid('Archive source was truncated while reading.');
      remaining -= data.length;
      yield data;
      progress.advance(data.length);
    }
    if (await file.length() != entry.size) {
      _invalid('Archive source size changed while reading.');
    }
  } finally {
    await file.close();
  }
}

/// Unlike a chunked converter emitting synchronously into a buffering stream
/// controller, the raw codec is drained one block at a time with backpressure.
Stream<List<int>> _coded(
  Stream<List<int>> input,
  RawZLibFilter codec,
  SidecarCancellation cancellation,
) async* {
  var fed = false;
  await for (final data in input) {
    cancellation.throwIfCancelled();
    if (data.isEmpty) continue;
    fed = true;
    codec.process(data, 0, data.length);
    while (true) {
      final bytes = codec.processed(flush: false);
      if (bytes == null) break;
      cancellation.throwIfCancelled();
      yield bytes;
    }
  }
  if (!fed) codec.process(const [], 0, 0);
  while (true) {
    cancellation.throwIfCancelled();
    final bytes = codec.processed(end: true);
    if (bytes == null) break;
    yield bytes;
  }
}

final class _ArchiveNames {
  final Map<String, bool> _members = {};
  int _nameBytes = 0;

  String add(String raw, {required bool directory}) {
    final name = _entryName(raw, directory: directory);
    chargeBytes(utf8.encode(name).length);
    final key = Platform.isWindows || Platform.isMacOS
        ? name.toLowerCase()
        : name;
    if (_members.containsKey(key)) {
      _unsafe('Archive contains duplicate destination paths.');
    }
    _members[key] = directory;
    return name;
  }

  void chargeBytes(int size) {
    _nameBytes += size;
    if (_nameBytes > _maxPathMetadata) {
      _limit('Archive path metadata is too large.');
    }
  }

  // Check known source names before emitting an archive. Extraction also
  // checks real directory paths, detecting collisions while streaming.
  Future<void> validateTree(SidecarCancellation cancellation) async {
    var checked = 0;
    for (final name in _members.keys) {
      if (++checked % 256 == 0) await Future<void>.delayed(Duration.zero);
      cancellation.throwIfCancelled();
      var slash = name.lastIndexOf('/');
      while (slash != -1) {
        if (_members[name.substring(0, slash)] == false) {
          _unsafe('Archive parent is not a directory.');
        }
        slash = name.lastIndexOf('/', slash - 1);
      }
    }
  }
}

final class _ArchiveTarget {
  final String root;
  final _ArchiveProgress progress;
  // A member may appear once, even when a child implicitly made its parent.
  final _names = _ArchiveNames();
  final _links = <String, String>{};
  int _createdNodes = 0;

  void _chargeNode() {
    if (++_createdNodes > _maxEntries) {
      _limit('Archive creates too many filesystem entries.');
    }
  }

  _ArchiveTarget(this.root, this.progress);

  Future<void> addSymlink(String raw, String linkTarget) async {
    progress.cancellation.throwIfCancelled();
    final name = _names.add(raw, directory: false);
    _names.chargeBytes(_linkTargetBytes(linkTarget));
    if (linkTarget.startsWith('/') ||
        linkTarget.contains(String.fromCharCode(92)) ||
        linkTarget.contains(':')) {
      _unsafe(
        'Archive symbolic link target must be a confined relative path: $name',
      );
    }
    _links[name] = linkTarget;
    progress.finishEntry();
  }

  Future<void> finishLinks() async {
    if (_links.isEmpty) return;
    await _names.validateTree(progress.cancellation);
    // Reserve and validate every link path before materializing any link.
    // The only acceptable targets are real files or directories in staging;
    // following another link (including in an intermediate segment) is forbidden.
    for (final entry in _links.entries) {
      final parts = entry.key.split('/');
      final parent = await _ensureDirectories(parts, parts.length - 1);
      _chargeNode();
      if (await FileSystemEntity.type(
            p.join(parent, parts.last),
            followLinks: false,
          ) !=
          FileSystemEntityType.notFound) {
        _unsafe(
          'Archive symbolic link collides with an existing path: ${entry.key}',
        );
      }
    }
    for (final entry in _links.entries) {
      await _checkLinkTarget(entry.key, entry.value);
    }
    for (final entry in _links.entries) {
      progress.cancellation.throwIfCancelled();
      await Link(
        p.joinAll([root, ...entry.key.split('/')]),
      ).create(entry.value);
    }
  }

  Future<void> _checkLinkTarget(String name, String target) async {
    final stack = name.split('/')..removeLast();
    final segments = target.split('/');
    if (segments.length > _maxPathDepth) {
      _limit('Archive link target is too deep.');
    }
    for (var i = 0; i < segments.length; i++) {
      progress.cancellation.throwIfCancelled();
      final segment = segments[i];
      if (segment.isEmpty || segment == '.') continue;
      if (segment == '..') {
        if (stack.isEmpty) {
          _unsafe(
            'Archive symbolic link points outside its target directory: $name',
          );
        }
        stack.removeLast();
        continue;
      }
      stack.add(segment);
      // Check each segment before processing subsequent segments such as '..'.
      // No links have been materialized yet, so this check never follows one.
      final type = await FileSystemEntity.type(
        p.joinAll([root, ...stack]),
        followLinks: false,
      );
      if (type != FileSystemEntityType.directory &&
          !(type == FileSystemEntityType.file && i == segments.length - 1)) {
        _unsafe(
          'Archive symbolic link target is missing or is not a regular archive entry: $name',
        );
      }
    }
  }

  Future<String> _ensureDirectories(List<String> parts, int count) async {
    var path = root;
    for (var i = 0; i < count; i++) {
      progress.cancellation.throwIfCancelled();
      path = p.join(path, parts[i]);
      final type = await FileSystemEntity.type(path, followLinks: false);
      if (type == FileSystemEntityType.notFound) {
        _chargeNode();
        await Directory(path).create();
      } else if (type != FileSystemEntityType.directory) {
        _unsafe('Archive parent is not a directory.');
      }
    }
    return path;
  }

  Future<void> add(
    String raw, {
    required bool directory,
    required int size,
    required Stream<List<int>> contents,
    int? crc,
  }) async {
    progress.cancellation.throwIfCancelled();
    final name = _names.add(raw, directory: directory);
    if (directory && size != 0) {
      _invalid('Archive directory contains a payload.');
    }
    final parts = name.isEmpty ? const <String>[] : name.split('/');
    final path = await _ensureDirectories(
      parts,
      directory ? parts.length : parts.length - 1,
    );
    if (directory) {
      // Still consume (and validate) compressed streams for empty ZIP dirs.
      await for (final data in contents) {
        if (data.isNotEmpty) _invalid('Archive directory contains a payload.');
      }
    } else {
      _chargeNode();
      final file = await _createNewFile(p.join(path, parts.last));
      final writer = await file.open(mode: FileMode.writeOnly);
      try {
        var remaining = size;
        var checksum = 0;
        await for (final chunk in contents) {
          progress.cancellation.throwIfCancelled();
          if (chunk.length > remaining) {
            _invalid('Archive entry expands beyond its declared size.');
          }
          await writer.writeFrom(chunk);
          remaining -= chunk.length;
          if (crc != null) checksum = getCrc32(chunk, checksum);
          progress.advance(chunk.length);
        }
        if (remaining != 0) _invalid('Archive entry is smaller than declared.');
        if (crc != null && crc != checksum) {
          _invalid('ZIP entry checksum mismatch.');
        }
      } finally {
        await writer.close();
      }
    }
    progress.finishEntry();
  }
}
