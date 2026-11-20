import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math';

import 'package:ffi/ffi.dart';
import 'package:host_deck_sidecar/protocol.dart';

const _atFdcwd = -100;
const _atSymlinkNoFollow = 0x100;
const _atRemovedir = 0x200;
const _atEmptyPath = 0x1000;
const _oWriteOnly = 1;
const _oCreate = 0x40;
const _oExclusive = 0x80;
const _oNonblock = 0x800;
// AArch64 UAPI overrides these two asm-generic flags.
final _oDirectory = Abi.current() == Abi.linuxArm64 ? 0x4000 : 0x10000;
final _oNoFollow = Abi.current() == Abi.linuxArm64 ? 0x8000 : 0x20000;
const _oCloexec = 0x80000;
const _oPath = 0x200000;

const errnoNoEntry = 2;
const errnoExists = 17;
const errnoCrossDevice = 18;
const _errnoInterrupted = 4;
const _errnoNotDirectory = 20;
const _errnoSymlinkLoop = 40;

const _permissions = 0x1ff;
const _privateDirectory = 0x1c0; // 0700
const _privateFile = 0x180; // 0600
const _utimeOmit = 1073741822;
const _renameNoReplace = 1;

final class _Timespec extends Struct {
  @Long()
  external int seconds;

  @Long()
  external int nanoseconds;
}

final class FileSnapshot {
  final int mode;
  final int inode;
  final int deviceMajor;
  final int deviceMinor;
  final int? mountId;
  final int size;
  final int mtimeSeconds;
  final int mtimeNanoseconds;
  final int ctimeSeconds;
  final int ctimeNanoseconds;

  FileSnapshot(ByteDataView data)
    : mode = data.u16(28),
      inode = data.u64(32),
      deviceMajor = data.u32(136),
      deviceMinor = data.u32(140),
      mountId = data.u32(0) & 0x1000 == 0 ? null : data.u64(144),
      size = data.u64(40),
      mtimeSeconds = data.s64(112),
      mtimeNanoseconds = data.u32(120),
      ctimeSeconds = data.s64(96),
      ctimeNanoseconds = data.u32(104);

  bool get isDirectory => mode & 0xf000 == 0x4000;
  bool get isFile => mode & 0xf000 == 0x8000;
  bool get isSymlink => mode & 0xf000 == 0xa000;
  int get permissions => mode & _permissions;
  DateTime get modified => DateTime.fromMicrosecondsSinceEpoch(
    mtimeSeconds * Duration.microsecondsPerSecond + mtimeNanoseconds ~/ 1000,
    isUtc: true,
  );

  bool sameIdentity(FileSnapshot other) =>
      inode == other.inode &&
      deviceMajor == other.deviceMajor &&
      deviceMinor == other.deviceMinor;

  bool sameMount(FileSnapshot other) =>
      deviceMajor == other.deviceMajor &&
      deviceMinor == other.deviceMinor &&
      mountId != null &&
      mountId == other.mountId;

  bool unchanged(FileSnapshot other, {bool checkCtime = true}) =>
      sameIdentity(other) &&
      mountId == other.mountId &&
      mode == other.mode &&
      size == other.size &&
      mtimeSeconds == other.mtimeSeconds &&
      mtimeNanoseconds == other.mtimeNanoseconds &&
      (!checkCtime ||
          (ctimeSeconds == other.ctimeSeconds &&
              ctimeNanoseconds == other.ctimeNanoseconds));
}

/// Linux statx has a fixed-width, native endian 256-byte ABI on both supported
/// architectures. Do not use libc's architecture-dependent struct stat here.
final class ByteDataView {
  final Pointer<Uint8> _buffer;
  ByteDataView(this._buffer);

  int u16(int offset) => (_buffer + offset).cast<Uint16>().value;
  int u32(int offset) => (_buffer + offset).cast<Uint32>().value;
  int u64(int offset) => (_buffer + offset).cast<Uint64>().value;
  int s64(int offset) => (_buffer + offset).cast<Int64>().value;
}

final class FileHandle {
  final int fd;
  final LinuxFileSystem _fs;
  bool _closed = false;

  FileHandle(this.fd, this._fs);

  // Dart's archive libraries accept paths, not directory handles. This procfs
  // path keeps the private staging directory anchored until archive I/O ends.
  String get procPath => '/proc/self/fd/$fd';
  FileSnapshot get snapshot => _fs._stat(fd, '', allowMissing: false)!;

  void close() {
    if (_closed) return;
    _closed = true;
    _fs._close(fd);
  }
}

final class FileLocation {
  final FileHandle parent;
  final String name;
  final List<FileSnapshot> ancestors;

  FileLocation(this.parent, this.name, this.ancestors);
}

final class FileStaging {
  final FileHandle parent;
  final String name;
  final FileHandle directory;

  FileStaging(this.parent, this.name, this.directory);
}

final class LinuxFileSystem {
  final DynamicLibrary _libc;

  LinuxFileSystem() : _libc = _loadLibc();

  static DynamicLibrary _loadLibc() {
    final abi = Abi.current();
    if (abi != Abi.linuxX64 && abi != Abi.linuxArm64) {
      throw const SidecarException(
        'unsupported_platform',
        'SideCar file operations require 64-bit Linux.',
      );
    }
    return DynamicLibrary.open('libc.so.6');
  }

  late final _openat = _libc
      .lookupFunction<
        Int Function(Int, Pointer<Utf8>, Int, VarArgs<(UnsignedInt,)>),
        int Function(int, Pointer<Utf8>, int, int)
      >('openat');
  late final _close = _libc
      .lookupFunction<Int Function(Int), int Function(int)>('close');
  late final _statx = _libc
      .lookupFunction<
        Int Function(Int, Pointer<Utf8>, Int, UnsignedInt, Pointer<Uint8>),
        int Function(int, Pointer<Utf8>, int, int, Pointer<Uint8>)
      >('statx');
  late final _readlinkat = _libc
      .lookupFunction<
        IntPtr Function(Int, Pointer<Utf8>, Pointer<Uint8>, UintPtr),
        int Function(int, Pointer<Utf8>, Pointer<Uint8>, int)
      >('readlinkat');
  late final _mkdirat = _libc
      .lookupFunction<
        Int Function(Int, Pointer<Utf8>, UnsignedInt),
        int Function(int, Pointer<Utf8>, int)
      >('mkdirat');
  late final _unlinkat = _libc
      .lookupFunction<
        Int Function(Int, Pointer<Utf8>, Int),
        int Function(int, Pointer<Utf8>, int)
      >('unlinkat');
  late final _renameat2 = _libc
      .lookupFunction<
        Int Function(Int, Pointer<Utf8>, Int, Pointer<Utf8>, UnsignedInt),
        int Function(int, Pointer<Utf8>, int, Pointer<Utf8>, int)
      >('renameat2');
  late final _chmod = _libc
      .lookupFunction<
        Int Function(Pointer<Utf8>, UnsignedInt),
        int Function(Pointer<Utf8>, int)
      >('chmod');
  late final _futimens = _libc
      .lookupFunction<
        Int Function(Int, Pointer<_Timespec>),
        int Function(int, Pointer<_Timespec>)
      >('futimens');
  late final _fdopendir = _libc
      .lookupFunction<Pointer<Void> Function(Int), Pointer<Void> Function(int)>(
        'fdopendir',
      );
  late final _readdir = _libc
      .lookupFunction<
        Pointer<Uint8> Function(Pointer<Void>),
        Pointer<Uint8> Function(Pointer<Void>)
      >('readdir64');
  late final _closedir = _libc
      .lookupFunction<Int Function(Pointer<Void>), int Function(Pointer<Void>)>(
        'closedir',
      );
  late final _read = _libc
      .lookupFunction<
        IntPtr Function(Int, Pointer<Uint8>, UintPtr),
        int Function(int, Pointer<Uint8>, int)
      >('read');
  late final _write = _libc
      .lookupFunction<
        IntPtr Function(Int, Pointer<Uint8>, UintPtr),
        int Function(int, Pointer<Uint8>, int)
      >('write');
  late final _errnoLocation = _libc
      .lookupFunction<Pointer<Int> Function(), Pointer<Int> Function()>(
        '__errno_location',
      );

  FileSystemException _error(String operation, String path, int errno) =>
      FileSystemException(
        operation,
        path,
        OSError('Linux errno $errno', errno),
      );

  int get _errno => _errnoLocation().value;

  FileLocation locate(String path) {
    if (path.isEmpty || path.contains('\u0000')) {
      throw const SidecarException('invalid_path', 'A valid path is required.');
    }
    final absolute = path.startsWith('/')
        ? path
        : '${Directory.current.path}/$path';
    final parts = absolute.split('/').where((part) => part.isNotEmpty).toList();
    if (parts.isEmpty || parts.last == '.' || parts.last == '..') {
      throw SidecarException(
        'invalid_path',
        'Not an operation endpoint: $path',
      );
    }
    final name = parts.removeLast();
    var parent = _open(_atFdcwd, '/', _oPath | _oDirectory | _oNoFollow);
    final ancestors = [parent.snapshot];
    try {
      for (final part in parts) {
        if (part == '.') continue;
        final next = openDirectory(parent, part, pathOnly: true);
        parent.close();
        parent = next;
        if (part == '..' && ancestors.length > 1) {
          ancestors.removeLast();
        } else if (part != '..') {
          ancestors.add(parent.snapshot);
        }
      }
      return FileLocation(parent, name, ancestors);
    } catch (_) {
      parent.close();
      rethrow;
    }
  }

  FileSnapshot? statAt(FileHandle parent, String name) =>
      _stat(parent.fd, name, allowMissing: true);

  // readlinkat does not follow the final component. An empty name reads the
  // link itself through an O_PATH | O_NOFOLLOW descriptor instead.
  String readLinkAt(FileHandle parent, String name) => using((arena) {
    const capacity = 4097;
    final path = name.toNativeUtf8(allocator: arena);
    final buffer = arena<Uint8>(capacity);
    final count = _retryIo(
      () => _readlinkat(parent.fd, path, buffer, capacity),
      parent,
    );
    if (count == capacity) {
      throw const SidecarException(
        'archive_limit',
        'Symbolic link target exceeds 4096 bytes.',
      );
    }
    try {
      // Keep a leading UTF-8 BOM verbatim, as with directory entry names.
      return utf8.decode([0x2f, ...buffer.asTypedList(count)]).substring(1);
    } on FormatException {
      throw const SidecarException(
        'invalid_path',
        'A symbolic link target is not UTF-8.',
      );
    }
  });

  FileSnapshot? _stat(int fd, String name, {required bool allowMissing}) =>
      using((arena) {
        final buffer = arena<Uint8>(256);
        final result = _statx(
          fd,
          name.toNativeUtf8(allocator: arena),
          _atSymlinkNoFollow | _atEmptyPath,
          0x17ff, // STATX_BASIC_STATS | STATX_MNT_ID
          buffer,
        );
        if (result == 0) return FileSnapshot(ByteDataView(buffer));
        final errno = _errno;
        if (allowMissing && errno == errnoNoEntry) return null;
        throw _error('Cannot inspect path', name, errno);
      });

  FileHandle _open(int parent, String path, int flags, [int mode = 0]) =>
      using((arena) {
        final fd = _openat(
          parent,
          path.toNativeUtf8(allocator: arena),
          flags | _oCloexec,
          mode,
        );
        if (fd >= 0) return FileHandle(fd, this);
        throw _error('Cannot open path', path, _errno);
      });

  FileHandle openDirectory(
    FileHandle parent,
    String name, {
    bool pathOnly = false,
  }) {
    try {
      return _open(
        parent.fd,
        name,
        _oDirectory | _oNoFollow | (pathOnly ? _oPath : 0),
      );
    } on FileSystemException catch (e) {
      final errno = e.osError?.errorCode;
      if ((errno == _errnoNotDirectory || errno == _errnoSymlinkLoop) &&
          statAt(parent, name)?.isSymlink == true) {
        throw SidecarException('unsupported_type', 'Symbolic link: $name');
      }
      rethrow;
    }
  }

  FileHandle openPath(FileHandle parent, String name) =>
      _open(parent.fd, name, _oPath | _oNoFollow);

  FileHandle openRegular(FileHandle pinned) =>
      _open(_atFdcwd, pinned.procPath, _oNonblock);

  FileHandle newFile(FileHandle parent, String name) => _open(
    parent.fd,
    name,
    _oWriteOnly | _oCreate | _oExclusive | _oNoFollow,
    _privateFile,
  );

  FileHandle newDirectory(FileHandle parent, String name) {
    using((arena) {
      if (_mkdirat(
            parent.fd,
            name.toNativeUtf8(allocator: arena),
            _privateDirectory,
          ) !=
          0) {
        throw _error('Cannot create staging directory', name, _errno);
      }
    });
    final handle = openDirectory(parent, name, pathOnly: true);
    try {
      // A restrictive umask must not make private staging inaccessible.
      _setMode(handle, _privateDirectory);
      return handle;
    } catch (_) {
      handle.close();
      rethrow;
    }
  }

  FileStaging createStaging(FileHandle parent) {
    final random = Random.secure();
    while (true) {
      final suffix = List.generate(
        16,
        (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      final name = '.hostdeck-sidecar-$suffix';
      try {
        return FileStaging(parent, name, newDirectory(parent, name));
      } on FileSystemException catch (e) {
        if (e.osError?.errorCode != errnoExists) rethrow;
      }
    }
  }

  Future<void> forEachName(
    FileHandle parent,
    Future<void> Function(String name) visit,
  ) async {
    final handle = openDirectory(parent, '.');
    final stream = _fdopendir(handle.fd);
    if (stream == nullptr) {
      final errno = _errno;
      handle.close();
      throw _error('Cannot list directory', parent.procPath, errno);
    }
    // fdopendir takes ownership of handle.fd. closedir closes it.
    try {
      while (true) {
        final errno = _errnoLocation();
        errno.value = 0;
        final entry = _readdir(stream);
        if (entry == nullptr) {
          if (errno.value != 0) {
            throw _error(
              'Cannot read directory entry',
              parent.procPath,
              errno.value,
            );
          }
          return;
        }
        // linux_dirent64: d_reclen at 16, d_name at 19. Decode strictly;
        // lossy name decoding could otherwise target a different entry.
        final length = (entry + 16).cast<Uint16>().value - 19;
        if (length < 1) {
          throw const SidecarException(
            'io_error',
            'Invalid Linux directory entry.',
          );
        }
        final bytes = (entry + 19).asTypedList(length);
        final stop = bytes.indexOf(0);
        if (stop < 0) {
          throw const SidecarException(
            'io_error',
            'Unterminated Linux directory entry.',
          );
        }
        final String name;
        try {
          // Conversion strips a leading UTF-8 BOM; a filesystem name does not.
          final decoded = utf8.decode([0x2f, ...bytes.take(stop)]);
          name = decoded.substring(1);
        } on FormatException {
          throw const SidecarException(
            'invalid_path',
            'A filename is not UTF-8.',
          );
        }
        if (name != '.' && name != '..') await visit(name);
      }
    } finally {
      _closedir(stream);
    }
  }

  Future<void> copyBytes(
    FileHandle source,
    FileHandle destination,
    int size,
    Future<void> Function(int bytes) onBytes,
  ) async {
    const chunk = 256 * 1024;
    final buffer = calloc<Uint8>(chunk);
    try {
      var copied = 0;
      do {
        final amount = min(chunk, size - copied + 1);
        final count = _retryIo(() => _read(source.fd, buffer, amount), source);
        if (count == 0) break;
        copied += count;
        if (copied > size) break;
        var written = 0;
        while (written < count) {
          final n = _retryIo(
            () => _write(destination.fd, buffer + written, count - written),
            destination,
          );
          if (n == 0) {
            throw FileSystemException('Zero-byte write', destination.procPath);
          }
          written += n;
        }
        await onBytes(count);
      } while (true);
      if (copied != size) {
        throw const SidecarException(
          'source_changed',
          'Source size changed during copy.',
        );
      }
    } finally {
      calloc.free(buffer);
    }
  }

  int _retryIo(int Function() call, FileHandle handle) {
    while (true) {
      final count = call();
      if (count >= 0) return count;
      final errno = _errno;
      if (errno != _errnoInterrupted) {
        throw _error('File transfer failed', handle.procPath, errno);
      }
    }
  }

  void applyMetadata(FileHandle handle, FileSnapshot snapshot) {
    // futimens requires an ordinary descriptor, while path-only handles also
    // survive setting restrictive metadata. Open before dropping access.
    final directory = snapshot.isDirectory ? openDirectory(handle, '.') : null;
    try {
      using((arena) {
        final times = arena<_Timespec>(2);
        times[0].nanoseconds = _utimeOmit;
        times[1].seconds = snapshot.mtimeSeconds;
        times[1].nanoseconds = snapshot.mtimeNanoseconds;
        if (_futimens((directory ?? handle).fd, times) != 0) {
          throw _error('Cannot set modification time', handle.procPath, _errno);
        }
      });
      _setMode(handle, snapshot.permissions);
    } finally {
      directory?.close();
    }
  }

  void _setMode(FileHandle handle, int mode) => using((arena) {
    final path = handle.procPath;
    if (_chmod(path.toNativeUtf8(allocator: arena), mode) != 0) {
      throw _error('Cannot set permissions', path, _errno);
    }
  });

  void ensurePrivateFile(FileHandle handle) => _setMode(handle, _privateFile);

  void ensureRemovable(FileHandle handle) =>
      _setMode(handle, _privateDirectory);

  void renameNoReplace(
    FileHandle fromParent,
    String fromName,
    FileHandle toParent,
    String toName,
  ) => using((arena) {
    if (_renameat2(
          fromParent.fd,
          fromName.toNativeUtf8(allocator: arena),
          toParent.fd,
          toName.toNativeUtf8(allocator: arena),
          _renameNoReplace,
        ) !=
        0) {
      throw _error(
        'Cannot atomically rename without replacement',
        toName,
        _errno,
      );
    }
  });

  void unlink(FileHandle parent, String name, {required bool directory}) =>
      using((arena) {
        if (_unlinkat(
              parent.fd,
              name.toNativeUtf8(allocator: arena),
              directory ? _atRemovedir : 0,
            ) !=
            0) {
          throw _error('Cannot remove path', name, _errno);
        }
      });

  Future<void> cleanStaging(FileStaging staging) async {
    final snapshot = statAt(staging.parent, staging.name);
    try {
      await _clearStagingDirectory(staging.directory);
      if (snapshot != null &&
          statAt(staging.parent, staging.name)?.sameIdentity(snapshot) ==
              true &&
          staging.directory.snapshot.sameIdentity(snapshot)) {
        unlink(staging.parent, staging.name, directory: true);
      }
    } finally {
      staging.directory.close();
    }
  }

  Future<void> _clearStagingDirectory(FileHandle directory) async {
    ensureRemovable(directory);
    // Collect names before unlinking entries, as mutating a directory during
    // iteration can invalidate the enumeration on some filesystems.
    final names = <String>[];
    await forEachName(directory, (name) async => names.add(name));
    for (final name in names) {
      final snapshot = statAt(directory, name);
      if (snapshot == null) continue;
      if (snapshot.isDirectory) {
        final child = openDirectory(directory, name, pathOnly: true);
        try {
          await _clearStagingDirectory(child);
        } finally {
          child.close();
        }
      }
      unlink(directory, name, directory: snapshot.isDirectory);
    }
  }
}
