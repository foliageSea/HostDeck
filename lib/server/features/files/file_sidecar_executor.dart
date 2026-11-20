import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:host_deck/server/core/ssh/shell_invocation.dart';
import 'package:host_deck/server/core/ssh/ssh_repository.dart';
import 'package:host_deck/server/core/ssh/ssh_session.dart';
import 'package:host_deck_sidecar/protocol.dart';
import 'package:path/path.dart' as p;

part 'file_sidecar_deployment.dart';
part 'file_sidecar_transport.dart';

abstract interface class FileSidecarExecutor {
  /// Returns null only when it is safe and appropriate to use legacy execution.
  Future<FileSidecarResult?> run(
    SshSession session, {
    required String id,
    required SidecarOperation operation,
    required String sourcePath,
    required String targetPath,
    required void Function(SidecarProgress) onProgress,
    required Future<void> cancellation,
    required bool Function() isCancelled,
  });
}

final class FileSidecarResult {
  final bool cancelled;

  const FileSidecarResult({required this.cancelled});
}

final class FileSidecarException implements Exception {
  final String code;
  final String message;

  const FileSidecarException(this.code, this.message);

  @override
  String toString() => message;
}

/// Deploys and runs the bundled Linux helper through the existing SSH client.
final class SshFileSidecarExecutor implements FileSidecarExecutor {
  final bool _enabled;
  final Directory _sidecarDirectory;
  final Duration _probeTimeout;
  final Duration _deploymentTimeout;
  final _SidecarTiming _timing;
  final SshRepository _repository;
  final _pendingDeployments =
      <(String, SSHClient), Future<_InstalledSidecar?>>{};

  SshFileSidecarExecutor(
    this._repository, {
    bool? enabled,
    String? sidecarDirectory,
    Duration probeTimeout = const Duration(seconds: 10),
    Duration deploymentTimeout = const Duration(minutes: 2),
    Duration startTimeout = const Duration(seconds: 15),
    Duration pingInterval = sidecarHeartbeatInterval,
    Duration heartbeatTimeout = sidecarHeartbeatTimeout,
    Duration operationTimeout = const Duration(hours: 24),
    Duration cancelGrace = const Duration(seconds: 5),
    Duration terminationGrace = const Duration(seconds: 3),
  }) : _enabled =
           enabled ?? Platform.environment['HOSTDECK_FILE_SIDECAR'] != 'off',
       _sidecarDirectory = Directory(
         sidecarDirectory ??
             Platform.environment['HOSTDECK_FILE_SIDECAR_DIR'] ??
             p.join(
               p.dirname(p.dirname(Platform.resolvedExecutable)),
               'sidecars',
             ),
       ),
       _probeTimeout = _positive(probeTimeout),
       _deploymentTimeout = _positive(deploymentTimeout),
       _timing = _SidecarTiming(
         start: _positive(startTimeout),
         ping: _positive(pingInterval),
         heartbeat: _positive(heartbeatTimeout),
         operation: _positive(operationTimeout),
         cancelGrace: _positive(cancelGrace),
         terminationGrace: _positive(terminationGrace),
       );

  @override
  Future<FileSidecarResult?> run(
    SshSession session, {
    required String id,
    required SidecarOperation operation,
    required String sourcePath,
    required String targetPath,
    required void Function(SidecarProgress) onProgress,
    required Future<void> cancellation,
    required bool Function() isCancelled,
  }) async {
    final cancelled = const FileSidecarResult(cancelled: true);
    if (isCancelled()) return cancelled;
    if (!_enabled || !_supports(operation, sourcePath, targetPath)) return null;
    if (!_taskId.hasMatch(id) ||
        id.length > 128 ||
        !_validPath(sourcePath) ||
        !_validPath(targetPath)) {
      throw const FileSidecarException('invalid_request', 'SideCar 请求无效。');
    }

    onProgress(const SidecarProgress(phase: SidecarPhase.deploying));
    if (isCancelled()) return cancelled;
    final (wasCancelled, installed) = await Future.any([
      _deploymentFor(session).then((installed) => (false, installed)),
      cancellation.then<(bool, _InstalledSidecar?)>(
        (_) => (true, null),
        onError: (Object _, StackTrace _) => (true, null),
      ),
    ]);
    if (wasCancelled || isCancelled()) return cancelled;
    if (installed == null) return null;

    final request = _encodeRequest(
      id,
      operation,
      installed.resolve(sourcePath),
      installed.resolve(targetPath),
    );
    final transport = _SidecarTransport(
      id: id,
      timing: _timing,
      onProgress: onProgress,
    );
    return transport.run(
      session,
      command: ShellInvocation.plain.wrap(
        'exec ${ShellInvocation.quote(installed.executable)} run --stdio',
      ),
      request: request,
      cancellation: cancellation,
      isCancelled: isCancelled,
    );
  }

  Future<_InstalledSidecar?> _deploymentFor(SshSession session) {
    // Use only the currently connected client. Never share an in-flight
    // deployment from a previous connection under a reused connection ID.
    final key = (session.connectionId, session.client);
    return _pendingDeployments.putIfAbsent(key, () async {
      try {
        return await _SidecarDeployment(
          _repository,
          session,
          _sidecarDirectory,
          _probeTimeout,
          _deploymentTimeout,
        ).install();
      } finally {
        _pendingDeployments.remove(key);
      }
    });
  }
}

final _taskId = RegExp(r'^[A-Za-z0-9_-]+$');

bool _validPath(String path) => path.isNotEmpty && !path.contains('\u0000');

// Keep this check before sending a run frame: even an unsupported-format
// result is not permission to replay a request that was already written.
bool _supports(SidecarOperation operation, String source, String target) {
  if (operation == SidecarOperation.copy ||
      operation == SidecarOperation.move) {
    return true;
  }
  final path = (operation == SidecarOperation.compress ? target : source)
      .toLowerCase();
  return path.endsWith('.zip') ||
      path.endsWith('.tar.gz') ||
      path.endsWith('.tgz') ||
      (operation == SidecarOperation.extract && path.endsWith('.tar'));
}

Duration _positive(Duration duration) {
  if (duration <= Duration.zero) throw ArgumentError.value(duration);
  return duration;
}

Uint8List _encodeRequest(
  String id,
  SidecarOperation operation,
  String source,
  String target,
) {
  try {
    return encodeSidecarFrame({
      'v': sidecarProtocolVersion,
      'id': id,
      'type': 'run',
      'operation': operation.name,
      'sourcePath': source,
      'targetPath': target,
    });
  } on FormatException {
    throw const FileSidecarException('invalid_request', 'SideCar 请求超出大小限制。');
  }
}
