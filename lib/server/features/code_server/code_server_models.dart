import 'dart:io';

/// 一次 code-server 会话的公开状态。
enum IdeSessionState { installing, starting, running, stopping, stopped, error }

/// 离线安装包元数据。
///
/// 包文件布局约定：`<root>/packages/<version>/linux-<arch>.tar.gz`，
/// 同目录下 `<id>.json` 保存元数据。
class IdePackage {
  final String id;
  final String version;
  final String arch;
  final String path;
  final int size;
  final String sha256;
  final DateTime createdAt;

  const IdePackage({
    required this.id,
    required this.version,
    required this.arch,
    required this.path,
    required this.size,
    required this.sha256,
    required this.createdAt,
  });

  String get fileName => 'linux-$arch.tar.gz';

  Map<String, dynamic> toJson() => {
    'id': id,
    'version': version,
    'arch': arch,
    'path': path,
    'size': size,
    'sha256': sha256,
    'createdAt': createdAt.toIso8601String(),
  };

  factory IdePackage.fromJson(Map<String, dynamic> json) => IdePackage(
    id: json['id'] as String,
    version: json['version'] as String,
    arch: json['arch'] as String,
    path: json['path'] as String,
    size: (json['size'] as num).toInt(),
    sha256: json['sha256'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
  );

  bool get exists => File(path).existsSync();

  static String buildId({required String version, required String arch}) =>
      '$version-linux-$arch';
}

/// 远端 Linux 目标机的安装前检查结果。
class IdePreflight {
  final String arch;
  final String? libc;
  final int? diskFreeBytes;
  final String? installedVersion;
  final List<String> issues;

  const IdePreflight({
    required this.arch,
    required this.libc,
    required this.diskFreeBytes,
    required this.installedVersion,
    required this.issues,
  });

  bool get supported => issues.isEmpty;

  bool get hasDiskSpace =>
      diskFreeBytes == null || diskFreeBytes! >= 1536 * 1024 * 1024;

  Map<String, dynamic> toJson() => {
    'arch': arch,
    'libc': libc,
    'diskFreeBytes': diskFreeBytes,
    'installedVersion': installedVersion,
    'issues': issues,
    'supported': supported,
  };
}

/// 远端启动结果。
class IdeLaunch {
  final int port;
  final int pid;
  final String version;
  final String sessionFile;

  const IdeLaunch({
    required this.port,
    required this.pid,
    required this.version,
    required this.sessionFile,
  });
}

/// 会话快照，用于 API 与代理解析。
class IdeSessionSnapshot {
  final String id;
  final String connectionId;
  final String hostKey;
  final String? folder;
  final IdeSessionState state;
  final String? error;
  final String? version;
  final double? progress;
  final DateTime? startedAt;

  const IdeSessionSnapshot({
    required this.id,
    required this.connectionId,
    required this.hostKey,
    required this.folder,
    required this.state,
    required this.error,
    required this.version,
    required this.progress,
    required this.startedAt,
  });

  IdeSessionSnapshot copyWith({
    IdeSessionState? state,
    String? error,
    String? version,
    double? progress,
    DateTime? startedAt,
    String? folder,
  }) => IdeSessionSnapshot(
    id: id,
    connectionId: connectionId,
    hostKey: hostKey,
    folder: folder ?? this.folder,
    state: state ?? this.state,
    error: error,
    version: version ?? this.version,
    progress: progress,
    startedAt: startedAt ?? this.startedAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'connectionId': connectionId,
    'hostKey': hostKey,
    'folder': folder,
    'state': state.name,
    'error': error,
    'version': version,
    'progress': progress,
    'startedAt': startedAt?.toIso8601String(),
  };
}

/// 代理目标。
class CodeServerUpstream {
  final String host;
  final int port;

  const CodeServerUpstream(this.host, this.port);
}

/// 由会话管理器实现：根据 sessionId 找到 code-server 的上游地址。
abstract class CodeServerUpstreamResolver {
  Future<CodeServerUpstream?> resolve(String sessionId);
}

/// 远端 code-server 的安装/启动/停止能力。
abstract class RemoteIdeProvider {
  Future<IdePreflight> preflight(
    String connectionId, {
    String? expectedVersion,
  });

  /// 安装离线包。`onProgress` 参数为已传输/总字节。
  Future<void> install(
    String connectionId,
    IdePackage package, {
    void Function(int received, int total)? onProgress,
    bool Function()? isCancelled,
  });

  Future<IdeLaunch> start(
    String connectionId, {
    required String sessionId,
    required String hostKey,
    required String version,
  });

  Future<void> stop(
    String connectionId, {
    required String sessionId,
    required int pid,
  });
}
