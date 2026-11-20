part of 'file_sidecar_executor.dart';

const _maxManifestBytes = 16 * 1024;
const _maxArtifactBytes = 32 * 1024 * 1024;
const _privateMode = 0x1c0; // 0700
const _readWriteMode = 0x180; // 0600
const _permissionBits = 0xfff; // includes setuid, setgid and sticky bits
const _groupWrite = 0x10;
const _otherWrite = 0x02;
const _groupOrOtherWrite = _groupWrite | _otherWrite;
const _privateCacheName = '.hostdeck-file-sidecar';
const _cleanupTimeout = Duration(seconds: 3);
final _sha256Pattern = RegExp(r'^[0-9a-f]{64}$');
final _versionPattern = RegExp(r'^[0-9A-Za-z][0-9A-Za-z.+_-]{0,127}$');
final _glibcPattern = RegExp(r'^glibc ([0-9]+)[.]([0-9]+)(?:[.][0-9]+)?$');

const _probeCommand =
    'LC_ALL=C; export LC_ALL; '
    'uname -s && uname -m && getconf GNU_LIBC_VERSION && id -u && '
    'command -v sha256sum >/dev/null';

class _InstalledSidecar {
  final String home;
  final String executable;

  const _InstalledSidecar(this.home, this.executable);

  // Do not lexically normalize '..': a remote symlink before it changes its
  // meaning. Also do not apply shell tilde expansion to literal SFTP names.
  String resolve(String path) =>
      path.startsWith('/') ? path : p.posix.join(home, path);
}

class _SidecarUnavailable implements Exception {
  const _SidecarUnavailable();
}

/// Select a different installation root instead of trusting a shared parent.
class _SidecarSharedParent implements Exception {
  const _SidecarSharedParent();
}

class _SidecarManifest {
  final String version;
  final Map<String, _SidecarArtifact> artifacts;

  const _SidecarManifest(this.version, this.artifacts);

  static Future<_SidecarManifest?> load(Directory directory) async {
    final path = p.join(directory.path, 'manifest.json');
    if (await FileSystemEntity.type(path, followLinks: false) ==
        FileSystemEntityType.notFound) {
      return null;
    }
    final bytes = await _readLocalFile(path, _maxManifestBytes);
    final Object? value;
    try {
      value = jsonDecode(utf8.decode(bytes));
    } on FormatException {
      throw _integrity('SideCar 清单不是有效的 UTF-8 JSON。');
    }
    if (value is! Map<String, dynamic> ||
        value['protocol'] is! int ||
        value['protocol'] != sidecarProtocolVersion) {
      throw _integrity('SideCar 清单协议版本无效。');
    }
    final version = value['version'];
    final entries = value['artifacts'];
    if (version is! String ||
        !_versionPattern.hasMatch(version) ||
        entries is! Map<String, dynamic>) {
      throw _integrity('SideCar 清单格式无效。');
    }
    final artifacts = <String, _SidecarArtifact>{};
    for (final arch in ['amd64', 'arm64']) {
      final entry = entries[arch];
      final expectedName = 'hostdeck-file-sidecar-linux-$arch';
      if (entry is! Map<String, dynamic> || entry['file'] != expectedName) {
        throw _integrity('SideCar 清单包含无效的文件名。');
      }
      final size = entry['size'];
      final digest = entry['sha256'];
      if (size is! int ||
          size <= 0 ||
          size > _maxArtifactBytes ||
          digest is! String ||
          !_sha256Pattern.hasMatch(digest)) {
        throw _integrity('SideCar 清单包含无效的大小或哈希。');
      }
      artifacts[arch] = _SidecarArtifact(expectedName, size, digest);
    }
    return _SidecarManifest(version, artifacts);
  }
}

class _SidecarArtifact {
  final String file;
  final int size;
  final String digest;

  const _SidecarArtifact(this.file, this.size, this.digest);

  Future<Uint8List> verifiedBytes(Directory directory) async {
    final bytes = await _readLocalFile(p.join(directory.path, file), size);
    if (bytes.length != size || sha256.convert(bytes).toString() != digest) {
      throw _integrity('本地 SideCar 文件大小或哈希校验失败。');
    }
    return bytes;
  }
}

Future<Uint8List> _readLocalFile(String path, int limit) async {
  if (await FileSystemEntity.type(path, followLinks: false) !=
      FileSystemEntityType.file) {
    throw _integrity('SideCar 安装包文件缺失或不是普通文件。');
  }
  final file = await File(path).open();
  try {
    if (await file.length() > limit) throw _integrity('SideCar 安装包超出大小限制。');
    final bytes = await file.read(limit + 1);
    if (bytes.length > limit) throw _integrity('SideCar 安装包超出大小限制。');
    return bytes;
  } finally {
    await file.close();
  }
}

Object? _decodeJson(String input) {
  try {
    return jsonDecode(input);
  } on FormatException {
    return null;
  }
}

FileSidecarException _integrity(String message) =>
    FileSidecarException('integrity_check_failed', message);

class _SidecarDeployment {
  final SshRepository _repository;
  final SshSession _session;
  final Directory _directory;
  final Duration _probeTimeout;
  final Duration _deploymentTimeout;
  final _stop = Completer<void>();
  SftpClient? _sftp;
  String? _stageDirectory;
  String? _stagedPath;

  _SidecarDeployment(
    this._repository,
    this._session,
    this._directory,
    this._probeTimeout,
    this._deploymentTimeout,
  );

  Future<_InstalledSidecar?> install() async {
    try {
      return await _install().timeout(
        _deploymentTimeout,
        onTimeout: () {
          _stop.complete();
          throw const FileSidecarException(
            'deployment_timeout',
            'SideCar 部署超时。',
          );
        },
      );
    } on _SidecarUnavailable {
      return null;
    } finally {
      if (!_stop.isCompleted) _stop.complete();
      final sftp = _sftp;
      if (sftp != null) {
        final staged = _stagedPath;
        final directory = _stageDirectory;
        if (staged != null) await _bestEffort(() => sftp.remove(staged));
        if (directory != null) await _bestEffort(() => sftp.rmdir(directory));
        await _bestEffort(sftp.close);
      }
    }
  }

  Future<_InstalledSidecar?> _install() async {
    // A missing package is a normal state in developer/unbundled installs.
    final manifest = await _SidecarManifest.load(_directory);
    if (manifest == null) return null;
    final SshExecResult probe;
    try {
      probe = await _exec(_probeCommand);
    } on SSHChannelRequestError {
      return null;
    }
    if (probe.exitCode == null || probe.truncated) {
      throw const FileSidecarException('probe_failed', 'SideCar 远端探测失败。');
    }
    if (probe.exitCode != 0) return null;
    final fields = probe.stdout.trim().split(RegExp(r'\r?\n'));
    if (fields.length != 4) {
      throw const FileSidecarException('probe_failed', 'SideCar 远端探测输出无效。');
    }
    final arch = switch (fields[1]) {
      'x86_64' || 'amd64' => 'amd64',
      'aarch64' || 'arm64' => 'arm64',
      _ => null,
    };
    final glibc = _glibcPattern.firstMatch(fields[2]);
    final major = int.tryParse(glibc?.group(1) ?? '');
    final minor = int.tryParse(glibc?.group(2) ?? '');
    if (fields[0] != 'Linux' ||
        arch == null ||
        major == null ||
        minor == null ||
        major < 2 ||
        (major == 2 && minor < 35)) {
      return null;
    }
    final uid = int.tryParse(fields[3]);
    if (uid == null || uid < 0) {
      throw const FileSidecarException('probe_failed', 'SideCar 远端用户标识无效。');
    }
    final artifact = manifest.artifacts[arch]!;
    final bytes = await artifact.verifiedBytes(_directory);

    // Keep this channel independent of the calling file task: two waiters
    // can share a deployment and either task may cancel/close its session.
    final sftp = await _session.runOperation(() async {
      _checkActive();
      try {
        final channel = await _session.client.sftp();
        if (_stop.isCompleted) {
          await _bestEffort(channel.close);
          _checkActive();
        }
        return _sftp = channel;
      } on SSHChannelRequestError {
        throw const _SidecarUnavailable();
      }
    });
    final home = await _request(() => sftp.absolute('.'), optional: true);
    if (!home.startsWith('/') ||
        !_validPath(home) ||
        p.posix.normalize(home) != home) {
      throw _integrity('SideCar 无法确定安全的远端主目录。');
    }
    final homeAttrs = await _request(() => sftp.stat(home, followLink: false));
    _checkDirectory(home, homeAttrs, uid);

    final cacheRoot = await _selectCacheRoot(sftp, home, uid);
    final directory = p.posix.join(cacheRoot, artifact.digest);
    await _ensureDirectory(sftp, directory, uid, private: true);
    final executable = p.posix.join(directory, artifact.file);
    final existing = await _stat(sftp, executable);
    if (existing != null) {
      await _verify(executable, existing, artifact, uid, manifest.version);
      return _InstalledSidecar(home, executable);
    }

    // SFTP open(create) cannot specify a mode, so open exclusively inside
    // our own 0700 directory. The staging directory is on the same filesystem.
    final random = Random.secure();
    final nonce = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final stageDir = p.posix.join(directory, '.upload-$nonce');
    final staged = p.posix.join(stageDir, artifact.file);
    _stageDirectory = stageDir;
    try {
      await _request(
        () => sftp.mkdir(stageDir, _mode(_privateMode)),
        optional: true,
      );
    } catch (_) {
      // A rejected mkdir did not create anything. If we timed out instead,
      // still try to remove our unique directory in the outer cleanup.
      if (!_stop.isCompleted) _stageDirectory = null;
      rethrow;
    }
    _stagedPath = staged;
    _checkDirectory(
      stageDir,
      await _request(() => sftp.stat(stageDir, followLink: false)),
      uid,
      private: true,
    );
    final file = await _request(
      () => sftp.open(
        staged,
        mode:
            SftpFileOpenMode.write |
            SftpFileOpenMode.create |
            SftpFileOpenMode.exclusive,
      ),
      optional: true,
    );
    try {
      await _request(() => file.setStat(_mode(_readWriteMode)), optional: true);
      await _request(() => file.writeBytes(bytes), optional: true);
      await _request(() => file.setStat(_mode(_privateMode)), optional: true);
    } catch (_) {
      await _bestEffort(file.close);
      rethrow;
    }
    await _request(file.close);
    await _verify(
      staged,
      await _request(() => sftp.stat(staged, followLink: false)),
      artifact,
      uid,
      manifest.version,
    );

    var published = await _stat(sftp, executable);
    if (published == null) {
      try {
        await _request(() => sftp.rename(staged, executable), optional: true);
      } on SftpStatusError {
        // A competing HostDeck process may have won a non-replacing rename.
        published = await _stat(sftp, executable);
        if (published == null) rethrow;
      }
    }
    if (published != null) {
      await _verify(executable, published, artifact, uid, manifest.version);
    }
    return _InstalledSidecar(home, executable);
  }

  Future<SshExecResult> _exec(String command) {
    _checkActive();
    return _repository.execWithResult(
      _session,
      command,
      login: false,
      timeout: _probeTimeout,
      maxOutputBytes: 4096,
      cancellation: _stop.future,
      isCancelled: () => _stop.isCompleted,
    );
  }

  Future<T> _request<T>(
    Future<T> Function() request, {
    bool optional = false,
  }) async {
    _checkActive();
    try {
      return await request();
    } on SftpStatusError catch (error) {
      if (optional &&
          (error.code == SftpStatusCode.permissionDenied ||
              error.code == SftpStatusCode.opUnsupported)) {
        throw const _SidecarUnavailable();
      }
      rethrow;
    }
  }

  void _checkActive() {
    if (_stop.isCompleted) {
      throw const FileSidecarException('deployment_timeout', 'SideCar 部署超时。');
    }
  }

  Future<SftpFileAttrs?> _stat(SftpClient sftp, String path) async {
    try {
      return await _request(() => sftp.stat(path, followLink: false));
    } on SftpStatusError catch (error) {
      if (error.code == SftpStatusCode.noSuchFile) return null;
      rethrow;
    }
  }

  Future<String> _selectCacheRoot(SftpClient sftp, String home, int uid) async {
    var parent = home;
    try {
      for (final component in ['.local', 'lib', 'hostdeck']) {
        parent = p.posix.join(parent, component);
        await _ensureDirectory(
          sftp,
          parent,
          uid,
          private: false,
          allowPrivateFallback: true,
        );
      }
    } on _SidecarSharedParent {
      // A common user-private-group umask makes the XDG parents 0775. Do
      // not modify them or place an executable anywhere underneath them.
      final alternative = p.posix.join(home, _privateCacheName);
      await _ensureDirectory(sftp, alternative, uid, private: true);
      return alternative;
    }
    final preferred = p.posix.join(parent, 'file-sidecar');
    await _ensureDirectory(sftp, preferred, uid, private: true);
    return preferred;
  }

  Future<void> _ensureDirectory(
    SftpClient sftp,
    String path,
    int uid, {
    required bool private,
    bool allowPrivateFallback = false,
  }) async {
    var attrs = await _stat(sftp, path);
    if (attrs == null) {
      try {
        await _request(
          () => sftp.mkdir(path, _mode(_privateMode)),
          optional: true,
        );
      } on SftpStatusError {
        attrs = await _stat(sftp, path);
        if (attrs == null) rethrow;
      }
    }
    _checkDirectory(
      path,
      attrs ?? await _request(() => sftp.stat(path, followLink: false)),
      uid,
      private: private,
      allowPrivateFallback: allowPrivateFallback,
    );
  }

  void _checkDirectory(
    String path,
    SftpFileAttrs attrs,
    int uid, {
    bool private = false,
    bool allowPrivateFallback = false,
  }) {
    final mode = attrs.mode;
    if (mode == null || !attrs.isDirectory || attrs.userID != uid) {
      throw _integrity('SideCar 安装目录不是当前 SSH 用户拥有的普通目录：$path');
    }
    final permissions = mode.value & _permissionBits;
    if (private) {
      if (permissions != _privateMode) {
        throw _integrity('SideCar 私有安装目录权限必须为 0700：$path');
      }
    } else if (permissions & _groupOrOtherWrite != 0) {
      if (allowPrivateFallback &&
          permissions & _groupOrOtherWrite == _groupWrite) {
        throw const _SidecarSharedParent();
      }
      throw _integrity('SideCar 安装目录不能对组或其他用户开放写权限：$path');
    }
  }

  Future<void> _verify(
    String path,
    SftpFileAttrs attrs,
    _SidecarArtifact artifact,
    int uid,
    String version,
  ) async {
    if (!attrs.isFile ||
        attrs.userID != uid ||
        attrs.size != artifact.size ||
        ((attrs.mode?.value ?? 0) & _permissionBits) != _privateMode) {
      throw _integrity('远端 SideCar 文件的类型、所有者、大小或权限无效。');
    }
    final quoted = ShellInvocation.quote(path);
    final checksum = await _exec('LC_ALL=C sha256sum < $quoted');
    final reported = checksum.stdout.trim().split(RegExp(r'\s+')).first;
    if (checksum.exitCode != 0 ||
        checksum.truncated ||
        reported != artifact.digest) {
      throw _integrity('远端 SideCar 文件哈希校验失败。');
    }
    final info = await _exec('exec $quoted --version --json');
    if (!info.truncated &&
        (info.exitCode == 126 || info.exitCode == 127) &&
        info.stdout.trim().isEmpty) {
      // Verified binary cannot start, e.g. a noexec home mount or missing loader.
      throw const _SidecarUnavailable();
    }
    final identity = _decodeJson(info.stdout);
    if (info.exitCode != 0 ||
        info.truncated ||
        identity is! Map<String, dynamic> ||
        identity['protocol'] is! int ||
        identity['protocol'] != sidecarProtocolVersion ||
        identity['version'] != version) {
      throw _integrity('远端 SideCar 版本或协议校验失败。');
    }
  }
}

SftpFileAttrs _mode(int permissions) =>
    SftpFileAttrs(mode: SftpFileMode.value(permissions));

Future<void> _bestEffort(Future<void> Function() cleanup) async {
  try {
    await cleanup().timeout(_cleanupTimeout);
  } catch (_) {
    // Never mask the original error or leave the task waiting on cleanup.
  }
}
