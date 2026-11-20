part of 'archive_operations.dart';

const _zipLocalSignature = 0x04034b50;
const _zipCentralSignature = 0x02014b50;
const _zipEndSignature = 0x06054b50;
const _zip64EndSignature = 0x06064b50;
const _zip64LocatorSignature = 0x07064b50;
const _zipDescriptorSignature = 0x08074b50;
const _zipUtf8 = 0x0800;
const _zipDescriptor = 0x0008;
const _zipStored = 0;
const _zipDeflate = 8;
const _zipUnix = 3;
const _zipMac = 19;
const _zipDirectoryMode = 0x4000;
const _zipRegularMode = 0x8000;
const _zipSymlinkMode = 0xa000;
// A link target is path metadata, not a potentially large file payload.
const _zipMaxPackedLinkBytes = 2 * _maxPathBytes;
const _u32Max = 0xffffffff;
const _u16Max = 0xffff;
const _le = Endian.little;

// Streaming ZIP adapter. archive's ZipEncoder buffers a complete compressed
// member, while its decoder eagerly allocates member metadata. Emit standard
// ZIP data descriptors and spool only the central directory to private scratch.
Future<void> _writeZip(
  List<ArchiveSourceEntry> entries,
  RandomAccessFile output,
  Directory staging,
  _ArchiveProgress progress,
) async {
  final scratch = await staging.createTemp('.sidecar-zip-');
  try {
    final centralFile = File(p.join(scratch.path, 'central'));
    final central = await centralFile.open(mode: FileMode.writeOnly);
    var zip64 = false;
    try {
      for (final entry in entries) {
        progress.cancellation.throwIfCancelled();
        final directory = entry.isDirectory;
        final name = _entryName(entry.name, directory: directory);
        final filename = utf8.encode(
          directory ? (name.isEmpty ? './' : '$name/') : name,
        );
        final linkTarget = entry.linkTarget;
        List<int>? linkBytes;
        if (linkTarget != null) {
          if (linkTarget.length > _maxPathBytes) {
            _limit('ZIP symbolic link target is too long.');
          }
          linkBytes = utf8.encode(linkTarget);
          _zipCheckLinkSize(linkBytes.length);
        }
        final offset = await output.position();
        final size = linkBytes?.length ?? (directory ? 0 : entry.size);
        // Use ZIP64 locally when even worst-case DEFLATE overhead could cross
        // the 32-bit limit, as the final compressed size is not known yet.
        final large = size >= 0xf0000000;
        final largeOffset = offset >= _u32Max;
        zip64 |= large || largeOffset;
        final method = directory || linkBytes != null
            ? _zipStored
            : _zipDeflate;
        final flags = _zipUtf8 | (method == _zipDeflate ? _zipDescriptor : 0);
        var crc = linkBytes == null ? 0 : getCrc32(linkBytes, 0);
        var packedSize = linkBytes?.length ?? 0;
        final date = _zipDosDate(entry.modified);
        final version = large || largeOffset ? 45 : 20;
        final localExtra = large ? _zip64Extra([size, 0]) : Uint8List(0);
        final local = ByteData(30)
          ..setUint32(0, _zipLocalSignature, _le)
          ..setUint16(4, version, _le)
          ..setUint16(6, flags, _le)
          ..setUint16(8, method, _le)
          ..setUint32(10, date, _le)
          ..setUint32(14, crc, _le)
          ..setUint32(18, large ? _u32Max : packedSize, _le)
          ..setUint32(22, large ? _u32Max : (linkBytes?.length ?? 0), _le)
          ..setUint16(26, filename.length, _le)
          ..setUint16(28, localExtra.length, _le);
        await output.writeFrom(local.buffer.asUint8List());
        await output.writeFrom(filename);
        await output.writeFrom(localExtra);
        if (linkBytes != null) {
          // Write only the validated, original target; never open the link.
          await output.writeFrom(linkBytes);
        } else if (!directory) {
          final compressed = _coded(
            _sourceBytes(entry, progress).map((bytes) {
              crc = getCrc32(bytes, crc);
              return bytes;
            }),
            RawZLibFilter.deflateFilter(raw: true),
            progress.cancellation,
          );
          await for (final bytes in compressed) {
            await output.writeFrom(bytes);
            packedSize += bytes.length;
          }
          final descriptor = ByteData(large ? 24 : 16)
            ..setUint32(0, _zipDescriptorSignature, _le)
            ..setUint32(4, crc, _le);
          if (large) {
            descriptor
              ..setUint64(8, packedSize, _le)
              ..setUint64(16, size, _le);
          } else {
            descriptor
              ..setUint32(8, packedSize, _le)
              ..setUint32(12, size, _le);
          }
          await output.writeFrom(descriptor.buffer.asUint8List());
        } else {
          await _sourceBytes(entry, progress).drain<void>();
        }
        final centralExtra = _zip64Extra([
          if (large) ...[size, packedSize],
          if (largeOffset) offset,
        ]);
        final mode =
            (entry.mode & 0x1ff) |
            (linkBytes != null
                ? _zipSymlinkMode
                : directory
                ? _zipDirectoryMode
                : _zipRegularMode);
        final header = ByteData(46)
          ..setUint32(0, _zipCentralSignature, _le)
          ..setUint16(4, (_zipUnix << 8) | version, _le)
          ..setUint16(6, version, _le)
          ..setUint16(8, flags, _le)
          ..setUint16(10, method, _le)
          ..setUint32(12, date, _le)
          ..setUint32(16, crc, _le)
          ..setUint32(20, large ? _u32Max : packedSize, _le)
          ..setUint32(24, large ? _u32Max : size, _le)
          ..setUint16(28, filename.length, _le)
          ..setUint16(30, centralExtra.length, _le)
          ..setUint32(38, (mode << 16) | (directory ? 0x10 : 0), _le)
          ..setUint32(42, largeOffset ? _u32Max : offset, _le);
        await central.writeFrom(header.buffer.asUint8List());
        await central.writeFrom(filename);
        await central.writeFrom(centralExtra);
        progress.finishEntry();
      }
    } finally {
      await central.close();
    }
    final centralStart = await output.position();
    final length = await centralFile.length();
    await for (final bytes in centralFile.openRead()) {
      progress.cancellation.throwIfCancelled();
      await output.writeFrom(bytes);
    }
    final count = entries.length;
    zip64 |= centralStart >= _u32Max || length >= _u32Max || count >= _u16Max;
    if (zip64) {
      final record = ByteData(76)
        ..setUint32(0, _zip64EndSignature, _le)
        ..setUint64(4, 44, _le)
        ..setUint16(12, 45, _le)
        ..setUint16(14, 45, _le)
        ..setUint64(24, count, _le)
        ..setUint64(32, count, _le)
        ..setUint64(40, length, _le)
        ..setUint64(48, centralStart, _le)
        ..setUint32(56, _zip64LocatorSignature, _le)
        ..setUint64(64, centralStart + length, _le)
        ..setUint32(72, 1, _le);
      await output.writeFrom(record.buffer.asUint8List());
    }
    final end = ByteData(22)
      ..setUint32(0, _zipEndSignature, _le)
      ..setUint16(8, zip64 ? _u16Max : count, _le)
      ..setUint16(10, zip64 ? _u16Max : count, _le)
      ..setUint32(12, zip64 ? _u32Max : length, _le)
      ..setUint32(16, zip64 ? _u32Max : centralStart, _le);
    await output.writeFrom(end.buffer.asUint8List());
  } finally {
    await scratch.delete(recursive: true);
  }
}

int _zipDosDate(DateTime value) {
  final local = value.toLocal();
  if (local.year < 1980) return 0x00210000;
  if (local.year > 2107) return 0xff9fbf7d;
  return ((local.year - 1980) << 25) |
      (local.month << 21) |
      (local.day << 16) |
      (local.hour << 11) |
      (local.minute << 5) |
      (local.second ~/ 2);
}

Uint8List _zip64Extra(List<int> fields) {
  if (fields.isEmpty) return Uint8List(0);
  final data = ByteData(4 + 8 * fields.length)
    ..setUint16(0, 1, _le)
    ..setUint16(2, 8 * fields.length, _le);
  for (var i = 0; i < fields.length; i++) {
    data.setUint64(4 + 8 * i, fields[i], _le);
  }
  return data.buffer.asUint8List();
}

Future<Uint8List> _zipRead(RandomAccessFile file, int offset, int count) async {
  await file.setPosition(offset);
  final data = await file.read(count);
  if (data.length != count) _invalid('Truncated ZIP structure.');
  return data;
}

Future<({int offset, int length, int count})> _zipCentralDirectory(
  RandomAccessFile file,
) async {
  final size = await file.length();
  final tailOffset = math.max(0, size - _u16Max - 22);
  final bytes = await _zipRead(file, tailOffset, size - tailOffset);
  final data = ByteData.sublistView(bytes);
  for (var i = bytes.length - 22; i >= 0; i--) {
    if (data.getUint32(i, _le) != _zipEndSignature ||
        data.getUint16(i + 20, _le) != bytes.length - i - 22) {
      continue;
    }
    if (data.getUint16(i + 4, _le) != 0 || data.getUint16(i + 6, _le) != 0) {
      _invalid('Split ZIP archives are unsupported.');
    }
    var count = data.getUint16(i + 10, _le);
    if (data.getUint16(i + 8, _le) != count) {
      _invalid('Split ZIP archives are unsupported.');
    }
    var length = data.getUint32(i + 12, _le);
    var offset = data.getUint32(i + 16, _le);
    var limit = tailOffset + i;
    // Some writers emit ZIP64 metadata even when the classic fields fit.
    if (limit >= 20) {
      final locator = ByteData.sublistView(
        await _zipRead(file, limit - 20, 20),
      );
      if (locator.getUint32(0, _le) == _zip64LocatorSignature) {
        final position = locator.getUint64(8, _le);
        if (locator.getUint32(4, _le) != 0 ||
            locator.getUint32(16, _le) != 1 ||
            position < 0 ||
            position > limit - 76) {
          _invalid('Invalid ZIP64 locator.');
        }
        final zip64 = ByteData.sublistView(await _zipRead(file, position, 56));
        if (zip64.getUint32(0, _le) != _zip64EndSignature ||
            zip64.getUint64(4, _le) != limit - 20 - position - 12 ||
            zip64.getUint32(16, _le) != 0 ||
            zip64.getUint32(20, _le) != 0 ||
            zip64.getUint64(24, _le) != zip64.getUint64(32, _le)) {
          _invalid('Invalid ZIP64 end record.');
        }
        count = zip64.getUint64(32, _le);
        length = zip64.getUint64(40, _le);
        offset = zip64.getUint64(48, _le);
        limit = position;
      }
    }
    if (offset < 0 ||
        length < 0 ||
        count < 0 ||
        offset > limit ||
        length != limit - offset ||
        count > length ~/ 46) {
      _invalid('Invalid ZIP central directory bounds.');
    }
    if (count > _maxEntries) _limit('Archive contains too many entries.');
    return (offset: offset, length: length, count: count);
  }
  _invalid('ZIP end record is missing.');
}

int _zipEntryType(ByteData header) {
  final attributes = header.getUint32(38, _le);
  final type = (attributes >> 16) & 0xf000;
  final host = header.getUint8(5);
  // Interpret a Unix symlink only when the writer declares Unix-style metadata.
  if ((type != 0 &&
          type != _zipRegularMode &&
          type != _zipDirectoryMode &&
          !(type == _zipSymlinkMode &&
              (host == _zipUnix || host == _zipMac))) ||
      attributes & 0x440 != 0) {
    _unsafe('Unsupported ZIP entry type or attributes.');
  }
  return type;
}

void _zipCheckLinkSize(int size) {
  if (size <= 0) _invalid('ZIP symbolic link target is empty or invalid.');
  if (size > _maxPathBytes) _limit('ZIP symbolic link target is too long.');
}

// Eagerly sum the central directory's declared file lengths using bounded
// reads. Link payloads are metadata and never contribute to byte progress.
// Extraction still validates every member's actual length and CRC.
Future<int> _zipExpandedSize(
  RandomAccessFile file,
  ({int offset, int length, int count}) central,
  SidecarCancellation cancellation,
) async {
  final quota = _ArchiveQuota();
  var position = central.offset;
  final end = position + central.length;
  for (var i = 0; i < central.count; i++) {
    cancellation.throwIfCancelled();
    if (end - position < 46) _invalid('Truncated ZIP central directory.');
    final header = ByteData.sublistView(await _zipRead(file, position, 46));
    if (header.getUint32(0, _le) != _zipCentralSignature) {
      _invalid('Invalid ZIP directory entry.');
    }
    var size = header.getUint32(24, _le);
    final name = header.getUint16(28, _le);
    final extra = header.getUint16(30, _le);
    final comment = header.getUint16(32, _le);
    final next = position + 46 + name + extra + comment;
    if (next > end) _invalid('Truncated ZIP metadata.');
    if (size == _u32Max) {
      final fields = await _zipRead(file, position + 46 + name, extra);
      size = _zipReadExtra(fields, [true, false, false]).fields[0] ?? size;
    }
    final link = _zipEntryType(header) == _zipSymlinkMode;
    if (link) _zipCheckLinkSize(size);
    quota.add(link ? 0 : size);
    position = next;
  }
  if (position != end) _invalid('ZIP central directory size mismatch.');
  return quota.bytes;
}

Future<void> _extractZip(File source, _ArchiveTarget target) async {
  final file = await source.open();
  try {
    final central = await _zipCentralDirectory(file);
    final end = central.offset + central.length;
    var position = central.offset;
    final quota = _ArchiveQuota();
    target.progress.bytesTotal = await _zipExpandedSize(
      file,
      central,
      target.progress.cancellation,
    );
    target.progress.entriesTotal = central.count;
    target.progress.report();
    for (var i = 0; i < central.count; i++) {
      target.progress.cancellation.throwIfCancelled();
      if (end - position < 46) _invalid('Truncated ZIP central directory.');
      final header = ByteData.sublistView(await _zipRead(file, position, 46));
      if (header.getUint32(0, _le) != _zipCentralSignature) {
        _invalid('Invalid ZIP directory entry.');
      }
      final flags = header.getUint16(8, _le);
      final method = header.getUint16(10, _le);
      // Bit 1 and 2 are DEFLATE compression hints, not a different format.
      if (flags &
                  ~(_zipUtf8 |
                      _zipDescriptor |
                      (method == _zipDeflate ? 6 : 0)) !=
              0 ||
          (method != _zipStored && method != _zipDeflate)) {
        _unsafe(
          'Encrypted ZIP entries and unsupported compression methods are not allowed.',
        );
      }
      final crc = header.getUint32(16, _le);
      var packedSize = header.getUint32(20, _le);
      var size = header.getUint32(24, _le);
      final filenameLength = header.getUint16(28, _le);
      final extraLength = header.getUint16(30, _le);
      final commentLength = header.getUint16(32, _le);
      if (header.getUint16(34, _le) != 0) {
        _invalid('Split ZIP archives are unsupported.');
      }
      final attributes = header.getUint32(38, _le);
      final type = _zipEntryType(header);
      final link = type == _zipSymlinkMode;
      var localOffset = header.getUint32(42, _le);
      final variableLength = filenameLength + extraLength;
      if (variableLength + commentLength > end - position - 46) {
        _invalid('Truncated ZIP metadata.');
      }
      if (filenameLength > _maxPathBytes) {
        _limit('Archive entry path is too long.');
      }
      final variable = await _zipRead(file, position + 46, variableLength);
      final nameBytes = Uint8List.sublistView(variable, 0, filenameLength);
      final extra = _zipReadExtra(
        Uint8List.sublistView(variable, filenameLength),
        [size == _u32Max, packedSize == _u32Max, localOffset == _u32Max],
      );
      size = extra.fields[0] ?? size;
      packedSize = extra.fields[1] ?? packedSize;
      localOffset = extra.fields[2] ?? localOffset;
      final name = _zipDecodeName(nameBytes, flags, extra.unicodePath);
      final directory =
          type == _zipDirectoryMode ||
          attributes & 0x10 != 0 ||
          name.endsWith('/');
      if ((type == _zipRegularMode || link) && directory) {
        _invalid('Conflicting ZIP entry types.');
      }
      if (link) {
        _zipCheckLinkSize(size);
        if (packedSize > _zipMaxPackedLinkBytes) {
          _limit('ZIP compressed symbolic link target is too long.');
        }
      }
      quota.add(link ? 0 : size);
      if (directory && (size != 0 || crc != 0)) {
        _invalid('ZIP directory contains a payload.');
      }
      if (packedSize < 0 ||
          (method == _zipStored && packedSize != size) ||
          (method == _zipDeflate && packedSize == 0)) {
        _invalid('Invalid ZIP member size.');
      }
      final dataOffset = await _zipLocalData(
        file,
        localOffset,
        central.offset,
        nameBytes,
        flags,
        method,
        crc,
        size,
        packedSize,
      );
      final raw = _zipPayload(
        file,
        dataOffset,
        packedSize,
        target.progress.cancellation,
      );
      final contents = method == _zipStored
          ? raw
          : _coded(
              raw,
              RawZLibFilter.inflateFilter(raw: true),
              target.progress.cancellation,
            );
      if (link) {
        await target.addSymlink(
          name,
          await _zipReadLinkTarget(contents, size, crc),
        );
      } else {
        await target.add(
          name,
          directory: directory,
          size: size,
          contents: contents,
          crc: crc,
        );
      }
      position += 46 + variableLength + commentLength;
    }
    if (position != end) _invalid('ZIP central directory size mismatch.');
  } finally {
    await file.close();
  }
}

Future<String> _zipReadLinkTarget(
  Stream<List<int>> contents,
  int size,
  int crc,
) async {
  final bytes = Uint8List(size);
  var offset = 0;
  await for (final chunk in contents) {
    if (chunk.length > bytes.length - offset) {
      _invalid('ZIP symbolic link target expands beyond its declared size.');
    }
    bytes.setRange(offset, offset + chunk.length, chunk);
    offset += chunk.length;
  }
  if (offset != size) {
    _invalid('ZIP symbolic link target is smaller than declared.');
  }
  if (getCrc32(bytes, 0) != crc) _invalid('ZIP entry checksum mismatch.');
  final target = utf8.decode(bytes);
  // The decoder strips an initial BOM. Here it is a literal filename
  // character and must be kept, just like './' and '../'.
  final bom =
      size >= 3 && bytes[0] == 0xef && bytes[1] == 0xbb && bytes[2] == 0xbf;
  return bom ? '\uFEFF$target' : target;
}

Future<int> _zipLocalData(
  RandomAccessFile file,
  int offset,
  int limit,
  Uint8List name,
  int flags,
  int method,
  int crc,
  int size,
  int packedSize,
) async {
  if (offset < 0 || offset > limit - 30) {
    _invalid('Invalid ZIP local header offset.');
  }
  final local = ByteData.sublistView(await _zipRead(file, offset, 30));
  if (local.getUint32(0, _le) != _zipLocalSignature ||
      flags != local.getUint16(6, _le) ||
      method != local.getUint16(8, _le) ||
      name.length != local.getUint16(26, _le)) {
    _invalid('ZIP local header does not match central directory.');
  }
  final extraLength = local.getUint16(28, _le);
  final dataOffset = offset + 30 + name.length + extraLength;
  if (dataOffset > limit || packedSize > limit - dataOffset) {
    _invalid('ZIP entry data lies outside payload area.');
  }
  final variable = await _zipRead(file, offset + 30, name.length + extraLength);
  for (var i = 0; i < name.length; i++) {
    if (name[i] != variable[i]) {
      _invalid('ZIP local and central filenames do not match.');
    }
  }
  final localSize = local.getUint32(22, _le);
  final localPacked = local.getUint32(18, _le);
  final large = localSize == _u32Max || localPacked == _u32Max;
  final extra = _zipReadExtra(Uint8List.sublistView(variable, name.length), [
    localSize == _u32Max,
    localPacked == _u32Max,
  ]);
  if (flags & _zipDescriptor == 0) {
    if (local.getUint32(14, _le) != crc ||
        (extra.fields[0] ?? localSize) != size ||
        (extra.fields[1] ?? localPacked) != packedSize) {
      _invalid('ZIP local and central sizes or checksum do not match.');
    }
  } else {
    final at = dataOffset + packedSize;
    final wide = large || size >= _u32Max || packedSize >= _u32Max;
    final length = wide ? 20 : 12;
    if (limit - at < length) _invalid('Truncated ZIP data descriptor.');
    final descriptor = ByteData.sublistView(
      await _zipRead(file, at, math.min(length + 4, limit - at)),
    );
    bool matches(int start) =>
        descriptor.lengthInBytes - start >= length &&
        descriptor.getUint32(start, _le) == crc &&
        (wide
                ? descriptor.getUint64(start + 4, _le)
                : descriptor.getUint32(start + 4, _le)) ==
            packedSize &&
        (wide
                ? descriptor.getUint64(start + 12, _le)
                : descriptor.getUint32(start + 8, _le)) ==
            size;
    if (!matches(0) &&
        (descriptor.getUint32(0, _le) != _zipDescriptorSignature ||
            !matches(4))) {
      _invalid('ZIP data descriptor does not match central directory.');
    }
  }
  return dataOffset;
}

({List<int?> fields, Uint8List? unicodePath}) _zipReadExtra(
  Uint8List bytes,
  List<bool> requiredFields,
) {
  final fields = List<int?>.filled(requiredFields.length, null);
  final data = ByteData.sublistView(bytes);
  Uint8List? unicodePath;
  var offset = 0;
  var foundZip64 = false;
  while (offset < bytes.length) {
    if (bytes.length - offset < 4) _invalid('Truncated ZIP extra field.');
    final id = data.getUint16(offset, _le);
    final size = data.getUint16(offset + 2, _le);
    offset += 4;
    if (size > bytes.length - offset) _invalid('Truncated ZIP extra field.');
    if (id == 1) {
      if (foundZip64) _invalid('Duplicate ZIP64 extra field.');
      foundZip64 = true;
      var cursor = offset;
      for (var i = 0; i < fields.length; i++) {
        if (!requiredFields[i]) continue;
        if (offset + size - cursor < 8) {
          _invalid('Truncated ZIP64 extra field.');
        }
        fields[i] = data.getUint64(cursor, _le);
        cursor += 8;
      }
    } else if (id == 0x7075) {
      if (unicodePath != null) _invalid('Duplicate ZIP Unicode path field.');
      unicodePath = Uint8List.sublistView(bytes, offset, offset + size);
    } else if (id == 0x756e || (id == 0x000d && size > 12)) {
      _unsafe('ZIP link/device metadata is not allowed.');
    }
    offset += size;
  }
  if (!foundZip64 && requiredFields.any((value) => value)) {
    _invalid('Missing ZIP64 extra field.');
  }
  return (fields: fields, unicodePath: unicodePath);
}

String _zipDecodeName(Uint8List bytes, int flags, Uint8List? unicodePath) {
  if (flags & _zipUtf8 != 0) return utf8.decode(bytes);
  if (unicodePath != null &&
      unicodePath.length >= 5 &&
      unicodePath[0] == 1 &&
      ByteData.sublistView(unicodePath).getUint32(1, _le) == getCrc32(bytes)) {
    return utf8.decode(Uint8List.sublistView(unicodePath, 5));
  }
  // ZIP's original filename encoding, IBM Code Page 437.
  const cp437 =
      'ÇüéâäàåçêëèïîìÄÅÉæÆôöòûùÿÖÜ¢£¥₧ƒáíóúñÑªº¿⌐¬½¼¡«»'
      '░▒▓│┤╡╢╖╕╣║╗╝╜╛┐└┴┬├─┼╞╟╚╔╩╦╠═╬╧╨╤╥╙╘╒╓╫╪┘┌'
      '█▄▌▐▀αßΓπΣσµτΦΘΩδ∞φε∩≡±≥≤⌠⌡÷≈°∙·√ⁿ²■ ';
  return String.fromCharCodes(
    bytes.map((byte) => byte < 128 ? byte : cp437.codeUnitAt(byte - 128)),
  );
}

Stream<List<int>> _zipPayload(
  RandomAccessFile file,
  int offset,
  int remaining,
  SidecarCancellation cancellation,
) async* {
  await file.setPosition(offset);
  while (remaining > 0) {
    cancellation.throwIfCancelled();
    final bytes = await file.read(math.min(remaining, _chunkSize));
    if (bytes.isEmpty) _invalid('Truncated ZIP member payload.');
    remaining -= bytes.length;
    yield bytes;
  }
}
