import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:logging/logging.dart';
import 'package:pointycastle/digests/sha256.dart';

import 'package:host_deck/server/core/ssh/ssh_repository.dart';
import 'package:host_deck/server/core/ssh/ssh_service.dart';
import 'package:host_deck/server/core/ssh/ssh_session.dart';
import 'package:host_deck/server/features/code_server/code_server_models.dart';

/// 安装过程中被调用方取消时抛出。
class IdeInstallCancelledException implements Exception {
  const IdeInstallCancelledException();

  @override
  String toString() => 'code-server 安装已取消';
}

/// 通过 SSH 在远端 Linux 主机上安装、启动、停止 code-server。
///
/// 只操作远端用户 HOME 下的目录，不需要 sudo：
/// - 版本目录：~/.local/lib/hostdeck/code-server/版本号/
/// - 数据目录：~/.local/share/hostdeck/code-server/hostKey/{data,extensions,logs,sessions}
class SshRemoteIdeProvider implements RemoteIdeProvider {
  /// 端口从 18090 + hash(hostKey) % 100 开始尝试。
  static const int portBase = 18090;
  static const int portRange = 100;
  static const int portRetries = 10;

  /// 安装后至少需要 1.5GB 可用空间（219MB 包 + 676MB 解压 + 余量）。
  static const int minDiskFreeBytes = 1536 * 1024 * 1024;

  static const Duration _probeTimeout = Duration(seconds: 30);
  static const Duration _versionTimeout = Duration(seconds: 30);
  static const Duration _launchTimeout = Duration(seconds: 45);
  static const Duration _stopTimeout = Duration(seconds: 30);
  static const Duration _archiveTimeout = Duration(minutes: 10);
  static const Duration _cleanupTimeout = Duration(seconds: 60);

  /// 首次打开大仓库时，VS Code 的递归文件监听会拖慢文件树。
  /// 只补充缺失项，不覆盖用户已有配置。
  static const Map<String, Object> _defaultWatcherExcludes = {
    '**/.git/objects/**': true,
    '**/.git/subtree-cache/**': true,
    '**/node_modules/**': true,
    '**/.dart_tool/**': true,
    '**/build/**': true,
    '**/dist/**': true,
    '**/release/**': true,
    '**/.fvm/**': true,
    '**/.gradle/**': true,
  };

  static const String _installRootSuffix = '.local/lib/hostdeck/code-server';
  static const String _dataRootSuffix = '.local/share/hostdeck/code-server';

  static const String _homeCommand = r'''printf '%s\n' "$HOME"''';
  static const String _libcCommand =
      r'getconf GNU_LIBC_VERSION 2>/dev/null || ldd --version 2>&1 | head -n 1';
  static const String _diskCommand = r'df -Pk "$HOME" 2>/dev/null';
  static const String _toolsCommand =
      'for tool in tar setsid nohup sha256sum; do '
      'if command -v "\$tool" >/dev/null 2>&1; then '
      "printf 'yes:%s\\n' \"\$tool\"; "
      "else printf 'no:%s\\n' \"\$tool\"; fi; done";
  static const String _hasSha256Command =
      'command -v sha256sum >/dev/null 2>&1';
  static const String _listeningPortsCommand =
      'ss -ltn 2>/dev/null || netstat -ltn 2>/dev/null';

  static const String _launchTemplate = r'''
mkdir -p __LOG_DIR__ __SESSION_DIR__ __DATA_DIR__ __EXTENSIONS_DIR__ || exit 1
: > __LOG_FILE__ || exit 1
inner=__INNER__
if command -v setsid >/dev/null 2>&1; then
  setsid nohup sh -c "$inner" >> __LOG_FILE__ 2>&1 < /dev/null &
else
  nohup sh -c "$inner" >> __LOG_FILE__ 2>&1 < /dev/null &
fi
sleep 1
pid_file=__PID_FILE__
pid=''
if [ -s "$pid_file" ]; then pid=$(cat "$pid_file"); rm -f "$pid_file"; fi
if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
  printf 'IDE_PID:%s\n' "$pid"
else
  printf 'IDE_PID:0\n'
  tail -n 20 __LOG_FILE__ >&2
  exit 1
fi
''';

  static const String _extractTemplate = r'''
set -e
rm -rf __PARTIAL__
mkdir -p __PARTIAL__
tar -xzf __ARCHIVE__ -C __PARTIAL__
rm -rf __STAGING__
if [ -x __PARTIAL__/bin/code-server ]; then
  mv __PARTIAL__ __STAGING__
elif [ -d __PARTIAL__/__ROOT_DIR__ ]; then
  mv __PARTIAL__/__ROOT_DIR__ __STAGING__
else
  echo '无法识别的离线包结构' >&2
  exit 41
fi
rm -rf __TARGET__
mv __STAGING__ __TARGET__
''';

  static const String _stopTemplate = r'''
pid=__PID__
if [ "$pid" -gt 0 ] 2>/dev/null; then
  kill -TERM "$pid" 2>/dev/null || true
  i=0
  while kill -0 "$pid" 2>/dev/null && [ "$i" -lt 20 ]; do
    sleep 0.2
    i=$((i+1))
  done
  if kill -0 "$pid" 2>/dev/null; then
    kill -KILL "$pid" 2>/dev/null || true
    i=0
    while kill -0 "$pid" 2>/dev/null && [ "$i" -lt 20 ]; do
      sleep 0.2
      i=$((i+1))
    done
  fi
  if kill -0 "$pid" 2>/dev/null; then exit 1; fi
fi
rm -f __SESSION_FILE__
''';

  static final RegExp _pathComponentPattern = RegExp(
    r'^[A-Za-z0-9][A-Za-z0-9._-]*$',
  );
  static final RegExp _sessionIdPattern = RegExp(r'^[A-Za-z0-9_-]{1,128}$');
  static final RegExp _versionLikePattern = RegExp(r'^\d+\.\d+');

  final SshService _sshService;
  final SshRepository _repository;
  final Logger _log = Logger('SshRemoteIdeProvider');

  /// 远端 HOME 按连接缓存，避免每个操作多一次往返。
  final Map<String, String> _remoteHomes = {};

  /// sessionId 到远端会话文件的全路径，由 start 记录，供 stop 精确清理。
  final Map<String, String> _sessionFiles = {};

  SshRemoteIdeProvider(this._sshService, this._repository);

  @override
  Future<IdePreflight> preflight(
    String connectionId, {
    String? expectedVersion,
  }) {
    return _withSession(
      connectionId,
      (session) => _preflight(session, expectedVersion: expectedVersion),
    );
  }

  @override
  Future<void> install(
    String connectionId,
    IdePackage package, {
    void Function(int received, int total)? onProgress,
    bool Function()? isCancelled,
  }) {
    return _withSession(
      connectionId,
      (session) => _install(
        session,
        package,
        onProgress: onProgress,
        isCancelled: isCancelled,
      ),
    );
  }

  @override
  Future<IdeLaunch> start(
    String connectionId, {
    required String sessionId,
    required String hostKey,
    required String version,
  }) {
    return _withSession(
      connectionId,
      (session) => _start(
        session,
        connectionId: connectionId,
        sessionId: sessionId,
        hostKey: hostKey,
        version: version,
      ),
    );
  }

  @override
  Future<void> stop(
    String connectionId, {
    required String sessionId,
    required int pid,
  }) {
    return _withSession(
      connectionId,
      (session) => _stop(
        session,
        connectionId: connectionId,
        sessionId: sessionId,
        pid: pid,
      ),
    );
  }

  @override
  Future<void> uninstall(String connectionId) => _withSession(connectionId, (
    session,
  ) async {
    final home = await _home(session);
    if (home == '/' ||
        home.split('/').any((part) => part == '..' || part == '.')) {
      throw StateError('远端 HOME 目录不安全，拒绝卸载。');
    }
    // 不跟随安装树任何父目录的符号链接，也不触碰 share 数据树。
    final script =
        r'''
set -e
base=__HOME__
for part in .local lib hostdeck code-server; do
  base="$base/$part"
  if [ -L "$base" ]; then
    printf '%s\n' '安装路径包含符号链接，拒绝卸载' >&2
    exit 1
  fi
  if [ -e "$base" ] && [ ! -d "$base" ]; then exit 1; fi
done
rm -rf -- "$base"
[ ! -e "$base" ] && [ ! -L "$base" ]
'''
            .replaceAll('__HOME__', _quote(home));
    final result = await _tryExec(session, script, timeout: _cleanupTimeout);
    if (result.exitCode != 0) {
      throw StateError('卸载 code-server 失败：${_commandError(result)}');
    }
    _remoteHomes.remove(connectionId);
  });

  /// 18090 + FNV-1a(hostKey) % 100，同一 hostKey 始终得到同一端口。
  static int preferredPortFor(String hostKey) {
    return portBase + (_stableHash(hostKey) % portRange);
  }

  Future<IdePreflight> _preflight(
    SshSession session, {
    String? expectedVersion,
  }) async {
    final home = await _home(session);
    final issues = <String>[];

    final archRaw =
        _firstNonEmptyLine(
          (await _tryExec(session, 'uname -m', timeout: _probeTimeout)).stdout,
        ) ??
        '';
    final arch = _mapArch(archRaw);
    if (arch == null) {
      issues.add(
        '不支持的远端架构：${archRaw.isEmpty ? '未知' : archRaw}'
        '（仅支持 x86_64/amd64 与 aarch64/arm64）',
      );
    }

    final libc = _firstNonEmptyLine(
      (await _tryExec(session, _libcCommand, timeout: _probeTimeout)).stdout,
    );
    final libcIssue = _libcIssue(libc);
    if (libcIssue != null) {
      issues.add(libcIssue);
    }

    final dfOutput = (await _tryExec(
      session,
      _diskCommand,
      timeout: _probeTimeout,
    )).stdout;
    final diskFreeBytes = _parseDiskFreeBytes(dfOutput);
    if (diskFreeBytes != null && diskFreeBytes < minDiskFreeBytes) {
      issues.add('磁盘可用空间不足（${_formatBytes(diskFreeBytes)}），至少需要 1.5GB');
    }

    final tools = _parseToolProbe(
      (await _tryExec(session, _toolsCommand, timeout: _probeTimeout)).stdout,
    );
    if (!tools.contains('tar')) {
      issues.add('远端缺少 tar，无法解压离线包');
    }
    if (!tools.contains('setsid') && !tools.contains('nohup')) {
      issues.add('远端缺少 setsid/nohup，无法后台启动 code-server');
    }

    final installedVersion = await _installedVersion(
      session,
      home,
      expectedVersion: expectedVersion,
    );

    return IdePreflight(
      arch: arch ?? (archRaw.isEmpty ? 'unknown' : archRaw),
      libc: libc,
      diskFreeBytes: diskFreeBytes,
      installedVersion: installedVersion,
      installRoot: '$home/$_installRootSuffix',
      dataRoot: '$home/$_dataRootSuffix',
      issues: issues,
    );
  }

  Future<void> _install(
    SshSession session,
    IdePackage package, {
    void Function(int received, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final version = package.version.trim();
    _validatePathComponent(version, field: 'version');
    _validatePathComponent(package.id, field: 'id');
    if (package.arch != 'amd64' && package.arch != 'arm64') {
      throw ArgumentError.value(package.arch, 'arch', '仅支持 amd64/arm64');
    }

    final archive = File(package.path);
    if (!archive.existsSync()) {
      throw ArgumentError.value(package.path, 'path', '离线包文件不存在');
    }
    _checkCancelled(isCancelled);

    final home = await _home(session);
    final installRoot = '$home/$_installRootSuffix';
    final dataRoot = '$home/$_dataRootSuffix';
    final archivePath = '$dataRoot/tmp/${package.id}.tar.gz';
    final partialRoot = '$installRoot/$version.partial';
    final stagingRoot = '$installRoot/$version.new';
    final targetRoot = '$installRoot/$version';

    await _ensureDir(session, '$dataRoot/tmp');
    await _ensureDir(session, installRoot);
    _checkCancelled(isCancelled);

    try {
      await _repository.writeFileStream(
        session,
        archivePath,
        _progressStream(
          file: archive,
          total: package.size,
          onProgress: onProgress,
          isCancelled: isCancelled,
        ),
      );
    } catch (error) {
      await _cleanupArtifacts(
        session,
        archivePath: archivePath,
        partialRoot: partialRoot,
        stagingRoot: stagingRoot,
      );
      rethrow;
    }

    onProgress?.call(package.size, package.size);
    _checkCancelled(isCancelled);

    try {
      await _verifyArchiveSha256(session, archivePath, package.sha256);
      await _extractArchive(
        session,
        version: version,
        arch: package.arch,
        archivePath: archivePath,
        partialRoot: partialRoot,
        stagingRoot: stagingRoot,
        targetRoot: targetRoot,
      );
    } catch (error) {
      await _cleanupArtifacts(
        session,
        archivePath: archivePath,
        partialRoot: partialRoot,
        stagingRoot: stagingRoot,
      );
      rethrow;
    }

    final installedVersion = await _installedVersion(
      session,
      home,
      expectedVersion: version,
    );
    if (installedVersion != version) {
      await _cleanupArtifacts(
        session,
        archivePath: archivePath,
        partialRoot: partialRoot,
        stagingRoot: stagingRoot,
        targetRoot: targetRoot,
      );
      throw StateError(
        '离线包装载校验失败：期望 $version，实际 ${installedVersion ?? '未知版本'}',
      );
    }

    await _cleanupArtifacts(
      session,
      archivePath: archivePath,
      partialRoot: partialRoot,
      stagingRoot: stagingRoot,
    );
    _log.info(
      'code-server $version 已安装到远端（connection=${session.connectionId}）',
    );
  }

  Future<IdeLaunch> _start(
    SshSession session, {
    required String connectionId,
    required String sessionId,
    required String hostKey,
    required String version,
  }) async {
    _validateSessionId(sessionId);
    _validatePathComponent(version, field: 'version');
    final resolvedHostKey = _resolveHostKey(connectionId, hostKey);
    _validatePathComponent(resolvedHostKey, field: 'hostKey');

    final home = await _home(session);
    final binary = '$home/$_installRootSuffix/$version/bin/code-server';
    final exists = await _tryExec(
      session,
      '[ -x ${_quote(binary)} ]',
      timeout: _probeTimeout,
    );
    if (exists.exitCode != 0) {
      throw StateError('远端尚未安装 code-server $version（$binary）');
    }

    final currentVersion = await _installedVersion(
      session,
      home,
      expectedVersion: version,
    );
    if (currentVersion != version) {
      throw StateError(
        '远端 code-server 版本不匹配：期望 $version，实际 ${currentVersion ?? '未知'}',
      );
    }

    final dataRoot = '$home/$_dataRootSuffix/$resolvedHostKey';
    final dataDir = '$dataRoot/data';
    final extensionsDir = '$dataRoot/extensions';
    await _ensureUserSettings(session, dataDir);
    final logDir = '$dataRoot/logs';
    final sessionDir = '$dataRoot/sessions';
    final logFile = '$logDir/code-server.log';
    final sessionFile = '$sessionDir/$sessionId.json';
    final pidFile = '$sessionDir/.$sessionId.pid';

    final preferred = preferredPortFor(resolvedHostKey);
    String? lastError;
    for (var attempt = 0; attempt < portRetries; attempt++) {
      final port = preferred + attempt;
      if (port > 65535) {
        break;
      }
      if (await _isPortListening(session, port)) {
        _log.fine('远端端口 $port 已被占用，尝试下一个端口');
        continue;
      }

      final args = <String>[
        '--auth',
        'none',
        '--bind-addr',
        '127.0.0.1:$port',
        '--enable-remote-storage',
        '--disable-telemetry',
        '--disable-update-check',
        '--disable-workspace-trust',
        '--user-data-dir',
        dataDir,
        '--extensions-dir',
        extensionsDir,
        '--idle-timeout-seconds',
        '3600',
      ];
      final result = await _tryExec(
        session,
        _buildLaunchCommand(
          binary: binary,
          args: args,
          logDir: logDir,
          sessionDir: sessionDir,
          dataDir: dataDir,
          extensionsDir: extensionsDir,
          logFile: logFile,
          pidFile: pidFile,
        ),
        timeout: _launchTimeout,
      );
      final pid = _parsePid(result.stdout);
      if (result.exitCode == 0 && pid != null && pid > 0) {
        try {
          await _writeSessionFile(
            session,
            sessionFile: sessionFile,
            sessionDir: sessionDir,
            sessionId: sessionId,
            connectionId: connectionId,
            hostKey: resolvedHostKey,
            port: port,
            pid: pid,
            version: version,
          );
        } catch (error) {
          await _terminateProcess(session, pid);
          rethrow;
        }
        _sessionFiles[sessionId] = sessionFile;
        _log.info(
          'code-server 已启动（connection=$connectionId, '
          'port=$port, pid=$pid, version=$version）',
        );
        return IdeLaunch(
          port: port,
          pid: pid,
          version: version,
          sessionFile: sessionFile,
        );
      }

      lastError = _commandError(result);
      _log.warning('在端口 $port 启动 code-server 失败：$lastError');
      if (!_isPortConflict(lastError)) {
        break;
      }
    }

    throw StateError(
      '启动 code-server 失败${lastError == null ? '' : '：$lastError'}',
    );
  }

  Future<void> _stop(
    SshSession session, {
    required String connectionId,
    required String sessionId,
    required int pid,
  }) async {
    _validateSessionId(sessionId);
    final home = await _home(session);
    final dataRoot = '$home/$_dataRootSuffix';
    final cachedSessionFile = _sessionFiles[sessionId];
    final sessionFileExpression = cachedSessionFile != null
        ? _quote(cachedSessionFile)
        : "${_quote(dataRoot)}/*/sessions/${_quote(sessionId)}.json";

    final script = _stopTemplate
        .replaceAll('__PID__', '$pid')
        .replaceAll('__SESSION_FILE__', sessionFileExpression);
    final result = await _tryExec(session, script, timeout: _stopTimeout);
    if (result.exitCode != 0) {
      throw StateError('停止 code-server 失败：${_commandError(result)}');
    }
    _sessionFiles.remove(sessionId);
    _log.info(
      'code-server 会话已停止（connection=$connectionId, '
      'session=$sessionId, pid=$pid）',
    );
  }

  Future<T> _withSession<T>(
    String connectionId,
    Future<T> Function(SshSession session) action,
  ) async {
    final session = await _sshService.createSftpSession(
      connectionId,
      purpose: SshSessionPurpose.codeServer,
    );
    try {
      return await action(session);
    } finally {
      try {
        await _sshService.closeSession(session.id);
      } catch (error) {
        _log.fine('关闭 code-server SSH 会话失败：$error');
      }
    }
  }

  Future<String> _home(SshSession session) async {
    final cached = _remoteHomes[session.connectionId];
    if (cached != null) {
      return cached;
    }

    final result = await _tryExec(
      session,
      _homeCommand,
      timeout: _probeTimeout,
    );
    final home = _firstNonEmptyLine(result.stdout) ?? '';
    if (!home.startsWith('/')) {
      throw StateError('无法解析远端 HOME 目录：${_commandError(result)}');
    }
    _remoteHomes[session.connectionId] = home;
    return home;
  }

  Future<void> _ensureUserSettings(SshSession session, String dataDir) async {
    final userDir = '$dataDir/User';
    final settingsPath = '$userDir/settings.json';
    try {
      await _ensureDir(session, userDir);
      final result = await _tryExec(
        session,
        'cat ${_quote(settingsPath)} 2>/dev/null',
        timeout: _probeTimeout,
      );
      final raw = result.stdout.trim();
      final settings = <String, dynamic>{};
      if (raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          settings.addAll(decoded);
        } else if (decoded is Map) {
          for (final entry in decoded.entries) {
            settings[entry.key.toString()] = entry.value;
          }
        } else {
          return;
        }
      }

      var changed = false;
      final watcherRaw = settings['files.watcherExclude'];
      final watcherExcludes = watcherRaw is Map
          ? Map<String, dynamic>.from(watcherRaw)
          : <String, dynamic>{};
      if (watcherRaw is! Map) changed = true;
      for (final entry in _defaultWatcherExcludes.entries) {
        if (!watcherExcludes.containsKey(entry.key)) {
          watcherExcludes[entry.key] = entry.value;
          changed = true;
        }
      }
      settings['files.watcherExclude'] = watcherExcludes;
      if (!settings.containsKey('search.followSymlinks')) {
        settings['search.followSymlinks'] = false;
        changed = true;
      }

      if (!changed) return;
      await _exec(
        session,
        "printf '%s' ${_quote(jsonEncode(settings))} > ${_quote(settingsPath)}",
        timeout: _probeTimeout,
        context: '写入 IDE 推荐设置',
      );
      _log.info('已为远端 IDE 补充文件监听排除项：$settingsPath');
    } catch (error) {
      _log.warning('写入远端 IDE 推荐设置失败：$error');
    }
  }

  Future<String?> _installedVersion(
    SshSession session,
    String home, {
    String? expectedVersion,
  }) async {
    final root = '$home/$_installRootSuffix';
    final expected = expectedVersion?.trim() ?? '';
    final command = expected.isNotEmpty
        ? '${_quote('$root/$expected/bin/code-server')} '
              '--version | head -n 1'
        : 'for bin in ${_quote(root)}/*/bin/code-server; do '
              '[ -x "\$bin" ] || continue; '
              '"\$bin" --version | head -n 1; '
              'break; done';

    // WSL/网络文件系统上刚 mv 完立刻执行偶发失败；重试几次再判定“未知版本”。
    SshExecResult? lastResult;
    for (var attempt = 0; attempt < 3; attempt++) {
      final result = await _tryExec(session, command, timeout: _versionTimeout);
      final parsed = _parseVersion(result.stdout);
      if (parsed != null) return parsed;
      lastResult = result;
      if (attempt < 2) {
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
    }

    final stdout = (lastResult?.stdout ?? '').trim();
    final stderr = (lastResult?.stderr ?? '').trim();
    _log.warning(
      '读取远端 code-server 版本失败：exit=${lastResult?.exitCode} '
      'stdout=${stdout.length > 200 ? stdout.substring(0, 200) : stdout} '
      'stderr=${stderr.length > 200 ? stderr.substring(0, 200) : stderr}',
    );
    return null;
  }

  Future<void> _verifyArchiveSha256(
    SshSession session,
    String archivePath,
    String expectedSha256,
  ) async {
    final expected = expectedSha256.trim().toLowerCase();
    if (expected.isEmpty) {
      _log.warning('离线包缺少 sha256，跳过远端校验');
      return;
    }

    final hasSha = await _tryExec(
      session,
      _hasSha256Command,
      timeout: _probeTimeout,
    );
    if (hasSha.exitCode != 0) {
      _log.warning('远端缺少 sha256sum，跳过离线包校验（依赖 SSH 传输完整性）');
      return;
    }

    final result = await _exec(
      session,
      'sha256sum ${_quote(archivePath)}',
      timeout: _archiveTimeout,
      context: '校验离线包',
    );
    final actual =
        _firstNonEmptyLine(
          result.stdout,
        )?.split(RegExp(r'\s+')).first.trim().toLowerCase() ??
        '';
    if (actual != expected) {
      throw StateError('离线包 sha256 校验失败：期望 $expected，实际 $actual');
    }
  }

  Future<void> _extractArchive(
    SshSession session, {
    required String version,
    required String arch,
    required String archivePath,
    required String partialRoot,
    required String stagingRoot,
    required String targetRoot,
  }) async {
    final script = _extractTemplate
        .replaceAll('__ARCHIVE__', _quote(archivePath))
        .replaceAll('__PARTIAL__', _quote(partialRoot))
        .replaceAll('__STAGING__', _quote(stagingRoot))
        .replaceAll('__TARGET__', _quote(targetRoot))
        .replaceAll('__ROOT_DIR__', _quote('code-server-$version-linux-$arch'));
    await _exec(session, script, timeout: _archiveTimeout, context: '解压离线包');
  }

  Future<void> _ensureDir(SshSession session, String path) async {
    await _exec(
      session,
      'mkdir -p ${_quote(path)}',
      timeout: _probeTimeout,
      context: '创建远端目录',
    );
  }

  Future<void> _cleanupArtifacts(
    SshSession session, {
    required String archivePath,
    required String partialRoot,
    required String stagingRoot,
    String? targetRoot,
  }) async {
    final paths = <String>[archivePath, partialRoot, stagingRoot, ?targetRoot];
    final script = paths.map((path) => 'rm -rf ${_quote(path)}').join('; ');
    try {
      await _repository.execWithResult(
        session,
        script,
        timeout: _cleanupTimeout,
        login: false,
      );
    } catch (error) {
      _log.warning('清理 code-server 安装残留失败：$error');
    }
  }

  Future<void> _terminateProcess(SshSession session, int pid) async {
    try {
      await _repository.execWithResult(
        session,
        'kill -TERM $pid 2>/dev/null || true; '
        'sleep 0.2; kill -KILL $pid 2>/dev/null || true',
        timeout: _stopTimeout,
        login: false,
      );
    } catch (error) {
      _log.fine('回滚 code-server 进程失败：$error');
    }
  }

  Future<bool> _isPortListening(SshSession session, int port) async {
    final result = await _tryExec(
      session,
      _listeningPortsCommand,
      timeout: _probeTimeout,
    );
    for (final line in const LineSplitter().convert(result.stdout)) {
      final fields = line.trim().split(RegExp(r'\s+'));
      if (fields.length < 4) {
        continue;
      }
      final localAddress = fields[3];
      final separator = localAddress.lastIndexOf(RegExp(r'[:.]'));
      if (separator < 0) {
        continue;
      }
      if (int.tryParse(localAddress.substring(separator + 1)) == port) {
        return true;
      }
    }
    return false;
  }

  String _buildLaunchCommand({
    required String binary,
    required List<String> args,
    required String logDir,
    required String sessionDir,
    required String dataDir,
    required String extensionsDir,
    required String logFile,
    required String pidFile,
  }) {
    final quotedArgs = args.map(_quote).join(' ');
    final inner =
        'printf \'%s\' "\$\$" > ${_quote(pidFile)}; '
        'exec ${_quote(binary)} $quotedArgs';
    return _launchTemplate
        .replaceAll('__LOG_DIR__', _quote(logDir))
        .replaceAll('__SESSION_DIR__', _quote(sessionDir))
        .replaceAll('__DATA_DIR__', _quote(dataDir))
        .replaceAll('__EXTENSIONS_DIR__', _quote(extensionsDir))
        .replaceAll('__LOG_FILE__', _quote(logFile))
        .replaceAll('__PID_FILE__', _quote(pidFile))
        .replaceAll('__INNER__', _quote(inner));
  }

  Future<void> _writeSessionFile(
    SshSession session, {
    required String sessionFile,
    required String sessionDir,
    required String sessionId,
    required String connectionId,
    required String hostKey,
    required int port,
    required int pid,
    required String version,
  }) async {
    final payload = jsonEncode({
      'id': sessionId,
      'connectionId': connectionId,
      'hostKey': hostKey,
      'port': port,
      'pid': pid,
      'version': version,
      'startedAt': DateTime.now().toUtc().toIso8601String(),
    });
    await _exec(
      session,
      'mkdir -p ${_quote(sessionDir)} && '
      'printf \'%s\' ${_quote(payload)} > ${_quote(sessionFile)}',
      timeout: _probeTimeout,
      context: '写入 code-server 会话文件',
    );
  }

  String _resolveHostKey(String connectionId, String hostKey) {
    final trimmed = hostKey.trim();
    if (trimmed.isNotEmpty) {
      return trimmed;
    }

    final targetKey = _sshService.metadataFor(connectionId)?.targetKey;
    if (targetKey == null) {
      throw StateError('缺少 hostKey，且无法解析 SSH 目标：$connectionId');
    }
    final digest = SHA256Digest().process(
      Uint8List.fromList(utf8.encode(targetKey)),
    );
    final hex = digest
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return hex.substring(0, 12);
  }

  Future<SshExecResult> _exec(
    SshSession session,
    String command, {
    required Duration timeout,
    required String context,
  }) async {
    final result = await _repository.execWithResult(
      session,
      command,
      timeout: timeout,
      login: false,
    );
    if (result.exitCode != null && result.exitCode != 0) {
      throw StateError('$context失败：${_commandError(result)}');
    }
    return result;
  }

  Future<SshExecResult> _tryExec(
    SshSession session,
    String command, {
    required Duration timeout,
  }) {
    return _repository.execWithResult(
      session,
      command,
      timeout: timeout,
      login: false,
    );
  }

  Stream<List<int>> _progressStream({
    required File file,
    required int total,
    required void Function(int received, int total)? onProgress,
    required bool Function()? isCancelled,
  }) async* {
    var received = 0;
    await for (final chunk in file.openRead()) {
      _checkCancelled(isCancelled);
      received += chunk.length;
      onProgress?.call(received, total > 0 ? total : received);
      yield chunk;
    }
  }

  static void _checkCancelled(bool Function()? isCancelled) {
    if (isCancelled?.call() ?? false) {
      throw const IdeInstallCancelledException();
    }
  }

  static void _validatePathComponent(String value, {required String field}) {
    if (!_pathComponentPattern.hasMatch(value)) {
      throw ArgumentError.value(value, field, '包含非法字符');
    }
  }

  static void _validateSessionId(String sessionId) {
    if (!_sessionIdPattern.hasMatch(sessionId)) {
      throw ArgumentError.value(sessionId, 'sessionId', '包含非法字符');
    }
  }

  static String? _mapArch(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'x86_64':
      case 'amd64':
        return 'amd64';
      case 'aarch64':
      case 'arm64':
        return 'arm64';
      default:
        return null;
    }
  }

  static String? _libcIssue(String? libc) {
    final text = libc?.trim() ?? '';
    if (text.isEmpty) {
      return '无法识别远端 libc，无法确认 glibc ≥ 2.28';
    }

    final lower = text.toLowerCase();
    if (lower.contains('musl')) {
      return '远端使用 musl libc（如 Alpine），code-server standalone 需要 glibc ≥ 2.28';
    }

    final match = RegExp(r'(\d+)\.(\d+)').firstMatch(lower);
    if (match == null) {
      return '无法识别远端 glibc 版本：$text';
    }
    final major = int.parse(match.group(1)!);
    final minor = int.parse(match.group(2)!);
    if (major < 2 || (major == 2 && minor < 28)) {
      return '远端 glibc 版本过低（$text），code-server 需要 ≥ 2.28';
    }
    return null;
  }

  static int? _parseDiskFreeBytes(String output) {
    var skippedHeader = false;
    for (final line in const LineSplitter().convert(output)) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      if (!skippedHeader) {
        skippedHeader = true;
        continue;
      }
      final fields = trimmed.split(RegExp(r'\s+'));
      if (fields.length < 4) {
        continue;
      }
      final availableKb = int.tryParse(fields[3]);
      if (availableKb != null) {
        return availableKb * 1024;
      }
    }
    return null;
  }

  static Set<String> _parseToolProbe(String output) {
    final available = <String>{};
    for (final line in const LineSplitter().convert(output)) {
      final trimmed = line.trim();
      if (trimmed.startsWith('yes:')) {
        available.add(trimmed.substring('yes:'.length));
      }
    }
    return available;
  }

  static String? _parseVersion(String output) {
    final line = _firstNonEmptyLine(output);
    if (line == null) {
      return null;
    }
    final token = line.split(RegExp(r'\s+')).first;
    final version = token.startsWith('v') || token.startsWith('V')
        ? token.substring(1)
        : token;
    return _versionLikePattern.hasMatch(version) ? version : null;
  }

  static int? _parsePid(String output) {
    final match = RegExp(r'IDE_PID:(\d+)').firstMatch(output);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  static String _commandError(SshExecResult result) {
    final stderr = result.stderr.trim();
    if (stderr.isNotEmpty) {
      return stderr;
    }
    final stdout = result.stdout.trim();
    if (stdout.isNotEmpty) {
      return stdout;
    }
    if (result.exitCode != null) {
      return 'exit=${result.exitCode}';
    }
    return '未知错误';
  }

  static bool _isPortConflict(String detail) {
    final lower = detail.toLowerCase();
    return lower.contains('eaddrinuse') ||
        lower.contains('address already in use');
  }

  static String? _firstNonEmptyLine(String output) {
    for (final line in const LineSplitter().convert(output)) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty) {
        return trimmed;
      }
    }
    return null;
  }

  static String _formatBytes(int bytes) {
    const units = ['B', 'KB', 'MB', 'GB'];
    var value = bytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    final digits = unit == 0 ? 0 : 1;
    return '${value.toStringAsFixed(digits)}${units[unit]}';
  }

  static int _stableHash(String value) {
    var hash = 0x811c9dc5;
    for (final byte in utf8.encode(value)) {
      hash ^= byte;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash;
  }

  static String _quote(String value) {
    return "'${value.replaceAll("'", "'\\''")}'";
  }
}
