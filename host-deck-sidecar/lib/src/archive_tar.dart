part of 'archive_operations.dart';

Future<void> _writeTarGzip(
  List<ArchiveSourceEntry> entries,
  RandomAccessFile output,
  _ArchiveProgress progress,
) async {
  final sink = _TarGzipSink(output, progress.cancellation);
  final writer = tarWritingSink(sink);
  try {
    for (final entry in entries) {
      progress.cancellation.throwIfCancelled();
      final name = _entryName(entry.name, directory: entry.isDirectory);
      final linkTarget = entry.linkTarget;
      final type = linkTarget != null
          ? TypeFlag.symlink
          : entry.isDirectory
          ? TypeFlag.dir
          : TypeFlag.reg;
      await writer.addStream(
        Stream.value(
          TarEntry(
            TarHeader(
              name: entry.isDirectory ? (name.isEmpty ? './' : '$name/') : name,
              mode: entry.mode & 0x1ff,
              modified: entry.modified,
              size: type == TypeFlag.reg ? entry.size : 0,
              typeFlag: type,
              linkName: linkTarget,
            ),
            linkTarget == null
                ? _sourceBytes(entry, progress)
                : const Stream<List<int>>.empty(),
          ),
        ),
      );
      sink.check();
      progress.finishEntry();
    }
  } finally {
    await writer.close();
  }
  sink.check();
}

/// tarWritingSink awaits addStream for each declared-size entry. Encode each
/// stream block and await the actual output write before requesting the next.
/// The synchronous add calls only queue small TAR headers and padding.
final class _TarGzipSink implements StreamSink<List<int>> {
  final RandomAccessFile _output;
  final SidecarCancellation _cancellation;
  final _codec = RawZLibFilter.deflateFilter(gzip: true);
  final _done = Completer<void>();
  Future<void> _pending = Future.value();
  Object? _error;
  StackTrace? _trace;

  _TarGzipSink(this._output, this._cancellation);

  void check() {
    final error = _error;
    if (error != null) Error.throwWithStackTrace(error, _trace!);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    _error ??= error;
    _trace ??= stackTrace ?? StackTrace.current;
  }

  @override
  Future<void> get done => _done.future;

  @override
  void add(List<int> data) {
    _pending = _pending.then((_) => _encode(data)).catchError(addError);
  }

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await _pending;
    check();
    await for (final data in stream) {
      await _encode(data);
    }
  }

  Future<void> _encode(List<int> data) async {
    if (_error != null || data.isEmpty) return;
    _cancellation.throwIfCancelled();
    _codec.process(data, 0, data.length);
    await _drain(end: false);
  }

  Future<void> _drain({required bool end}) async {
    while (true) {
      _cancellation.throwIfCancelled();
      final bytes = _codec.processed(flush: end, end: end);
      if (bytes == null) return;
      await _output.writeFrom(bytes);
    }
  }

  Future<void>? _closing;

  @override
  Future<void> close() => _closing ??= _finish();

  Future<void> _finish() async {
    await _pending;
    if (_error == null) {
      try {
        await _drain(end: true);
      } catch (error, trace) {
        addError(error, trace);
      }
    }
    _done.complete();
  }
}

const _tarBlock = 512;
const _tarMetadataLimit = 64 * 1024;
const _tarMetadataTotalLimit = 16 * 1024 * 1024;

// The general-purpose TarReader can read and allocate GNU sparse maps before
// exposing a member, and can accumulate global PAX state across records. This
// framing adapter handles ordinary TAR and bounded PAX/GNU name and link
// metadata, rejecting exotic members before allocating or writing payloads.
Future<void> _extractTar(
  File source,
  _ArchiveTarget target, {
  required bool compressed,
}) async {
  final cancellation = target.progress.cancellation;
  final raw = compressed
      ? _verifiedGzip(source, cancellation)
      : source.openRead();
  final reader = _TarBlocks(raw, cancellation);
  final quota = _ArchiveQuota();
  _TarPaxFields? pax;
  String? gnuPath;
  String? gnuLink;
  var metadataBytes = 0;
  try {
    while (true) {
      final header = await reader.read(_tarBlock);
      if (header.every((byte) => byte == 0)) {
        if (pax != null ||
            gnuPath != null ||
            gnuLink != null ||
            !(await reader.read(_tarBlock)).every((byte) => byte == 0)) {
          _invalid('Invalid end of TAR archive.');
        }
        await reader.finish();
        break;
      }
      _tarChecksum(header);
      final type = header[156];
      final headerSize = _tarNumber(Uint8List.sublistView(header, 124, 136));
      if (type == 120 || type == 103 || type == 76 || type == 75) {
        // PAX x/g, GNU L/K.
        final padding = (-headerSize) % _tarBlock;
        if (headerSize > _tarMetadataLimit ||
            _tarBlock + headerSize + padding >
                _tarMetadataTotalLimit - metadataBytes) {
          _limit('TAR metadata is too large.');
        }
        // Bound all metadata framing, including header blocks and padding.
        metadataBytes += _tarBlock + headerSize + padding;
        final data = await reader.read(headerSize);
        await reader.read(padding);
        if (type == 76) {
          if (gnuPath != null || pax != null) {
            _invalid('Conflicting TAR path headers.');
          }
          gnuPath = _tarString(data, 0, data.length);
        } else if (type == 75) {
          if (gnuLink != null || pax != null) {
            _invalid('Conflicting TAR link headers.');
          }
          gnuLink = _tarString(data, 0, data.length);
        } else {
          final global = type == 103;
          if (pax != null || gnuPath != null || gnuLink != null) {
            _invalid('Conflicting TAR metadata headers.');
          }
          final fields = _tarPax(data, global: global);
          if (!global) pax = fields;
        }
        continue;
      }
      final symlink = type == 50; // '2'
      if (!symlink && type != 0 && type != 48 && type != 53) {
        _unsafe('TAR hard links and special entries are not allowed.');
      }
      final link = pax?.link ?? gnuLink;
      if (!symlink && (link != null || header[157] != 0)) {
        _unsafe('Unexpected TAR link target.');
      }
      final name = pax?.path ?? gnuPath ?? _tarHeaderName(header);
      final size = pax?.size ?? headerSize;
      if (symlink && (size != 0 || headerSize != 0)) {
        _invalid('TAR symbolic link contains a payload.');
      }
      quota.add(size);
      pax = null;
      gnuPath = null;
      gnuLink = null;
      if (symlink) {
        await target.addSymlink(name, link ?? _tarString(header, 157, 257));
      } else {
        final directory = type == 53 || (type == 0 && name.endsWith('/'));
        await target.add(
          name,
          directory: directory,
          size: size,
          contents: reader.payload(size),
        );
        await reader.read((-size) % _tarBlock);
      }
    }
  } finally {
    await reader.close();
  }
}

/// Dart's zlib streaming filter accepts end-of-input after all output has
/// been produced, even when a GZIP trailer is absent. Validate the CRC and
/// size independently. SideCar accepts a single standard GZIP member.
Stream<List<int>> _verifiedGzip(
  File source,
  SidecarCancellation cancellation,
) async* {
  final file = await source.open();
  try {
    final length = await file.length();
    if (length < 20) _invalid('Truncated GZIP archive.');
    final magic = await file.read(3);
    if (magic.length != 3 ||
        magic[0] != 0x1f ||
        magic[1] != 0x8b ||
        magic[2] != 8) {
      _invalid('Invalid GZIP signature or method.');
    }
    await file.setPosition(length - 8);
    final end = await file.read(8);
    if (end.length != 8) _invalid('Truncated GZIP trailer.');
    final trailer = ByteData.sublistView(end);
    var crc = 0;
    var size = 0;
    await for (final data in _coded(
      _zipPayload(file, 0, length, cancellation),
      RawZLibFilter.inflateFilter(gzip: true),
      cancellation,
    )) {
      crc = getCrc32(data, crc);
      size = (size + data.length) & _u32Max;
      yield data;
    }
    if (crc != trailer.getUint32(0, _le) || size != trailer.getUint32(4, _le)) {
      _invalid('GZIP trailer checksum or size mismatch.');
    }
  } finally {
    await file.close();
  }
}

void _tarChecksum(Uint8List header) {
  final checksum = _tarNumber(Uint8List.sublistView(header, 148, 156));
  var unsigned = 0;
  var signed = 0;
  for (var i = 0; i < header.length; i++) {
    final byte = (i >= 148 && i < 156) ? 32 : header[i];
    unsigned += byte;
    signed += byte < 128 ? byte : byte - 256;
  }
  if (checksum != unsigned && checksum != signed) {
    _invalid('Invalid TAR header checksum.');
  }
}

int _tarNumber(Uint8List field) {
  // Binary GNU/base-256 fields use the top bit as an encoding marker and
  // the next bit as a sign bit. Reject negatives and checked-overflow sizes.
  if (field[0] & 0x80 != 0) {
    if (field[0] & 0x40 != 0) _invalid('Negative TAR size.');
    var value = field[0] & 0x3f;
    for (var i = 1; i < field.length; i++) {
      if (value > (0x7fffffffffffffff - field[i]) ~/ 256) {
        _limit('TAR numeric field is too large.');
      }
      value = value * 256 + field[i];
    }
    return value;
  }
  final octal = ascii
      .decode(field)
      .replaceFirst(RegExp(r'^[ ]+'), '')
      .replaceFirst(RegExp(r'[\x00 ]+$'), '');
  if (octal.isEmpty) return 0;
  if (!RegExp(r'^[0-7]+$').hasMatch(octal)) {
    _invalid('Invalid TAR numeric field.');
  }
  return int.parse(octal, radix: 8);
}

String _tarString(Uint8List data, int start, int end) {
  final nul = data.indexOf(0, start);
  if (nul >= 0 && nul < end) {
    for (var i = nul + 1; i < end; i++) {
      if (data[i] != 0) _invalid('Data after the end of a TAR name.');
    }
    end = nul;
  }
  return utf8.decode(Uint8List.sublistView(data, start, end));
}

String _tarHeaderName(Uint8List header) {
  final name = _tarString(header, 0, 100);
  // USTAR stores a separate prefix; the GNU layout uses that area for
  // timestamps/sparse metadata, hence the precise magic check.
  if (header[257] == 117 &&
      header[258] == 115 &&
      header[259] == 116 &&
      header[260] == 97 &&
      header[261] == 114 &&
      header[262] == 0) {
    final prefix = _tarString(header, 345, 500);
    if (prefix.isNotEmpty) return '$prefix/$name';
  }
  return name;
}

typedef _TarPaxFields = ({String? path, String? link, int? size});

_TarPaxFields _tarPax(Uint8List bytes, {required bool global}) {
  final data = Uint8List.sublistView(bytes);
  String? path;
  String? link;
  int? size;
  var offset = 0;
  while (offset < data.length) {
    final space = data.indexOf(32, offset);
    if (space <= offset || space - offset > 6) {
      _invalid('Invalid TAR PAX record length.');
    }
    var length = 0;
    for (var i = offset; i < space; i++) {
      final digit = data[i] - 48;
      if (digit < 0 || digit > 9) _invalid('Invalid TAR PAX record length.');
      length = length * 10 + digit;
    }
    final end = offset + length;
    if (end <= space + 3 || end > data.length || data[end - 1] != 10) {
      _invalid('Truncated TAR PAX record.');
    }
    final equals = data.indexOf(61, space + 1);
    if (equals <= space + 1 || equals >= end - 1) {
      _invalid('Malformed TAR PAX record.');
    }
    final key = utf8.decode(Uint8List.sublistView(data, space + 1, equals));
    if (key.startsWith('GNU.sparse.') ||
        key == 'SCHILY.realsize' ||
        key == 'SCHILY.filetype') {
      _unsafe('TAR sparse files and special entries are not allowed.');
    }
    if (key == 'path' || key == 'linkpath' || key == 'size') {
      if (global) {
        _invalid('TAR global paths, link paths or sizes are not supported.');
      }
      final value = utf8.decode(
        Uint8List.sublistView(data, equals + 1, end - 1),
      );
      if (key == 'path') {
        if (path != null) _invalid('Duplicate TAR PAX path.');
        path = value;
      } else if (key == 'linkpath') {
        if (link != null) _invalid('Duplicate TAR PAX link path.');
        link = value;
      } else {
        if (size != null || !RegExp(r'^[0-9]+$').hasMatch(value)) {
          _invalid('Invalid TAR PAX size.');
        }
        size = int.tryParse(value);
        if (size == null) _limit('TAR PAX size is too large.');
      }
    }
    offset = end;
  }
  return (path: path, link: link, size: size);
}

final class _TarBlocks {
  final StreamIterator<List<int>> _source;
  final SidecarCancellation _cancellation;
  Uint8List _chunk = Uint8List(0);
  int _at = 0;

  _TarBlocks(Stream<List<int>> source, this._cancellation)
    : _source = StreamIterator(source);

  Future<bool> _next() async {
    _cancellation.throwIfCancelled();
    while (_at == _chunk.length) {
      if (!await _source.moveNext()) return false;
      final bytes = _source.current;
      _chunk = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
      _at = 0;
    }
    return true;
  }

  Future<Uint8List> read(int length) async {
    final result = Uint8List(length);
    var read = 0;
    while (read != length) {
      if (!await _next()) _invalid('Truncated TAR archive.');
      final count = math.min(length - read, _chunk.length - _at);
      result.setRange(read, read + count, _chunk, _at);
      read += count;
      _at += count;
    }
    return result;
  }

  Stream<List<int>> payload(int remaining) async* {
    while (remaining != 0) {
      if (!await _next()) _invalid('Truncated TAR member.');
      final count = math.min(remaining, _chunk.length - _at);
      final bytes = Uint8List.sublistView(_chunk, _at, _at + count);
      _at += count;
      remaining -= count;
      yield bytes;
    }
  }

  Future<void> finish() async {
    // Consume gzip to EOF to validate the trailer; allow common zero tar
    // blocking padding while bounding excessive decompressed trailing data.
    var padding = 0;
    while (await _next()) {
      padding += _chunk.length - _at;
      if (padding > 1024 * 1024) _limit('Excessive TAR end padding.');
      for (var i = _at; i < _chunk.length; i++) {
        if (_chunk[i] != 0) _invalid('Unexpected data after TAR end.');
      }
      _at = _chunk.length;
    }
  }

  Future<void> close() => _source.cancel();
}
