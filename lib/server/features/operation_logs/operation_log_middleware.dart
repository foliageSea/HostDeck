import 'dart:async';
import 'dart:convert';

import 'package:shelf/shelf.dart';

import 'package:host_deck/server/features/operation_logs/operation_log_service.dart';
import 'package:host_deck/server/features/port_forwards/port_forward_repository.dart';
import 'package:host_deck/server/features/servers/server_config.dart';
import 'package:host_deck/server/features/servers/server_repository.dart';

Middleware operationLogMiddleware(
  OperationLogService service,
  ServerRepository serverRepository,
  PortForwardRepository portForwardRepository,
) {
  final policies = _policies(serverRepository, portForwardRepository);
  return (innerHandler) {
    return (request) async {
      final policy = _findPolicy(policies, request.method, request.url.path);
      if (policy == null) {
        return innerHandler(request);
      }

      final preparedRequest = await _prepareRequest(request);
      final metadata = await _OperationMetadata.fromRequest(
        preparedRequest,
        policy,
      );
      var response = await innerHandler(preparedRequest);

      if (response.statusCode < 400 &&
          response.mimeType == 'text/event-stream') {
        return response.change(
          body: _observeSseOperation(
            response.read(),
            service,
            policy,
            metadata,
          ),
        );
      }

      String? errorMessage;
      if (response.statusCode >= 400 &&
          response.mimeType == 'application/json') {
        final body = await response.readAsString();
        response = response.change(body: body);
        errorMessage = _errorMessageFromBody(body);
      }

      if (response.statusCode < 400) {
        service.success(
          category: policy.category,
          action: policy.action,
          target: metadata.target,
          connectionId: metadata.connectionId,
        );
      } else {
        service.failure(
          category: policy.category,
          action: policy.action,
          target: metadata.target,
          connectionId: metadata.connectionId,
          error: errorMessage ?? 'HTTP ${response.statusCode}',
        );
      }

      return response;
    };
  };
}

Stream<List<int>> _observeSseOperation(
  Stream<List<int>> source,
  OperationLogService service,
  _OperationPolicy policy,
  _OperationMetadata metadata,
) async* {
  var scanBuffer = '';
  var completed = false;
  var failed = false;
  var recorded = false;

  void recordSuccess() {
    if (recorded) return;
    recorded = true;
    service.success(
      category: policy.category,
      action: policy.action,
      target: metadata.target,
      connectionId: metadata.connectionId,
    );
  }

  void recordFailure(Object error) {
    if (recorded) return;
    recorded = true;
    service.failure(
      category: policy.category,
      action: policy.action,
      target: metadata.target,
      connectionId: metadata.connectionId,
      error: error,
    );
  }

  try {
    await for (final chunk in source) {
      scanBuffer += utf8.decode(chunk, allowMalformed: true);
      failed = failed || scanBuffer.contains('event: error\n');
      completed = completed || scanBuffer.contains('event: done\n');
      if (scanBuffer.length > 256) {
        scanBuffer = scanBuffer.substring(scanBuffer.length - 256);
      }
      yield chunk;
    }

    if (failed) {
      recordFailure('SSE operation reported an error');
    } else if (completed) {
      recordSuccess();
    } else {
      recordFailure('SSE operation ended without a completion event');
    }
  } catch (error) {
    recordFailure(error);
    rethrow;
  } finally {
    if (!recorded) {
      recordFailure('SSE operation was cancelled');
    }
  }
}

Future<Request> _prepareRequest(Request request) async {
  if (request.mimeType != 'application/json') {
    return request;
  }

  final body = await request.readAsString();
  Map<String, dynamic>? data;
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) {
      data = decoded;
    }
  } catch (_) {
    // The controller remains responsible for reporting malformed JSON.
  }

  return request.change(body: body, context: {_requestDataContextKey: data});
}

String? _errorMessageFromBody(String body) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) {
      return decoded['message']?.toString();
    }
  } catch (_) {
    // A non-JSON error response has no structured message to record.
  }
  return null;
}

const _requestDataContextKey = 'operation-log.request-data';

class _OperationMetadata {
  final String? target;
  final String? connectionId;

  const _OperationMetadata({this.target, this.connectionId});

  static Future<_OperationMetadata> fromRequest(
    Request request,
    _OperationPolicy policy,
  ) async {
    final data =
        request.context[_requestDataContextKey] as Map<String, dynamic>?;
    final query = request.url.queryParameters;
    final connectionId =
        _string(data?['connectionId']) ?? query['connectionId'];
    String? target;
    try {
      target = await policy.targetResolver(request, data, policy);
    } catch (_) {
      // Audit metadata must never turn a successful operation into a failure.
    }
    return _OperationMetadata(target: target, connectionId: connectionId);
  }
}

String? _string(Object? value) {
  final result = value?.toString().trim();
  return result == null || result.isEmpty ? null : result;
}

String? _firstNonEmpty(Iterable<String?> values) {
  for (final value in values) {
    if (value != null && value.isNotEmpty) {
      return value;
    }
  }
  return null;
}

class _OperationPolicy {
  final String method;
  final RegExp path;
  final String category;
  final String action;
  final _TargetResolver targetResolver;

  _OperationPolicy(
    this.method,
    String path,
    this.category,
    this.action, {
    _TargetResolver? targetResolver,
  }) : path = RegExp('^$path\$'),
       targetResolver = targetResolver ?? _defaultTarget;

  String? targetFromPath(String requestPath) {
    final match = path.firstMatch(requestPath);
    return match != null && match.groupCount > 0 ? match.group(1) : null;
  }
}

typedef _TargetResolver =
    FutureOr<String?> Function(
      Request request,
      Map<String, dynamic>? data,
      _OperationPolicy policy,
    );

_OperationPolicy? _findPolicy(
  Iterable<_OperationPolicy> policies,
  String method,
  String path,
) {
  for (final policy in policies) {
    if (policy.method == method && policy.path.hasMatch(path)) {
      return policy;
    }
  }
  return null;
}

String? _defaultTarget(
  Request request,
  Map<String, dynamic>? data,
  _OperationPolicy policy,
) {
  return _firstNonEmpty([
    _string(data?['path']),
    _string(data?['oldPath']),
    _string(data?['newPath']),
    _string(data?['source']),
    _string(data?['archivePath']),
    _string(data?['command']),
    _string(data?['projectName']),
    _string(data?['sourceImage']),
    _string(data?['image']),
    _string(data?['name']),
    _string(data?['containerId']),
    _string(data?['serverId']),
    _string(request.url.queryParameters['path']),
    _string(request.url.queryParameters['connectionId']),
    policy.targetFromPath(request.url.path),
  ]);
}

Future<String?> _connectionTarget(
  Request _,
  Map<String, dynamic>? data,
  ServerRepository serverRepository,
) async {
  final serverId = int.tryParse(data?['serverId']?.toString() ?? '');
  if (serverId != null) {
    final server = serverRepository.getServer(serverId);
    if (server != null) {
      return _serverTarget(server);
    }
  }

  return _formatHostTarget(
    _string(data?['username']),
    _string(data?['host']),
    _string(data?['port']),
  );
}

String? _serverTargetFromRequest(
  Request request,
  Map<String, dynamic>? data,
  _OperationPolicy policy,
  ServerRepository serverRepository,
) {
  final directTarget = _formatHostTarget(
    _string(data?['username']),
    _string(data?['host']),
    _string(data?['port']),
  );
  if (directTarget != null) {
    return directTarget;
  }

  final id = int.tryParse(request.url.pathSegments.last);
  final server = id == null ? null : serverRepository.getServer(id);
  return server == null
      ? _defaultTarget(request, data, policy)
      : _serverTarget(server);
}

String? _disconnectTarget(
  Request request,
  Map<String, dynamic>? data,
  _OperationPolicy _,
) {
  return _string(request.url.queryParameters['connectionId']) ??
      _string(data?['connectionId']);
}

String? _portForwardTarget(
  Request request,
  Map<String, dynamic>? data,
  _OperationPolicy policy,
  PortForwardRepository portForwardRepository,
) {
  final bindHost = _string(data?['bindHost']);
  final localPort = _string(data?['localPort']);
  final remoteHost = _string(data?['remoteHost']);
  final remotePort = _string(data?['remotePort']);
  if (bindHost != null &&
      localPort != null &&
      remoteHost != null &&
      remotePort != null) {
    return _formatPortForwardTarget(
      bindHost,
      localPort,
      remoteHost,
      remotePort,
    );
  }

  final ruleId = int.tryParse(policy.targetFromPath(request.url.path) ?? '');
  if (ruleId != null) {
    final rule = portForwardRepository.getRule(ruleId);
    if (rule != null) {
      return _formatPortForwardTarget(
        rule.bindHost,
        rule.localPort.toString(),
        rule.remoteHost,
        rule.remotePort.toString(),
      );
    }
  }

  return _defaultTarget(request, data, policy);
}

String _formatPortForwardTarget(
  String bindHost,
  String localPort,
  String remoteHost,
  String remotePort,
) {
  return '$bindHost:$localPort -> $remoteHost:$remotePort';
}

String _serverTarget(ServerConfig server) {
  return '${server.username}@${server.host}:${server.port}';
}

String? _formatHostTarget(String? username, String? host, String? port) {
  if (username == null || host == null || port == null) {
    return null;
  }
  return '$username@$host:$port';
}

List<_OperationPolicy> _policies(
  ServerRepository serverRepository,
  PortForwardRepository portForwardRepository,
) => [
  _OperationPolicy(
    'POST',
    r'api/connect',
    'auth',
    'connect',
    targetResolver: (request, data, _) =>
        _connectionTarget(request, data, serverRepository),
  ),
  _OperationPolicy(
    'POST',
    r'api/connect/test',
    'auth',
    'testConnect',
    targetResolver: (request, data, _) =>
        _connectionTarget(request, data, serverRepository),
  ),
  _OperationPolicy(
    'DELETE',
    r'api/connect',
    'auth',
    'disconnect',
    targetResolver: _disconnectTarget,
  ),
  _OperationPolicy('POST', r'api/agent/exec', 'agent', 'exec'),
  _OperationPolicy('POST', r'api/agent/file/read', 'agent', 'read'),
  _OperationPolicy('POST', r'api/agent/file/write', 'agent', 'write'),
  _OperationPolicy('POST', r'api/agent/patch', 'agent', 'patch'),
  _OperationPolicy(
    'POST',
    r'api/servers',
    'server',
    'create',
    targetResolver: (request, data, policy) =>
        _serverTargetFromRequest(request, data, policy, serverRepository),
  ),
  _OperationPolicy(
    'PUT',
    r'api/servers/([^/]+)',
    'server',
    'update',
    targetResolver: (request, data, policy) =>
        _serverTargetFromRequest(request, data, policy, serverRepository),
  ),
  _OperationPolicy(
    'DELETE',
    r'api/servers/([^/]+)',
    'server',
    'delete',
    targetResolver: (request, data, policy) =>
        _serverTargetFromRequest(request, data, policy, serverRepository),
  ),
  _OperationPolicy('POST', r'api/processes/([^/]+)/kill', 'process', 'kill'),
  _OperationPolicy(
    'POST',
    r'api/port-forwards',
    'portForward',
    'create',
    targetResolver: (request, data, policy) =>
        _portForwardTarget(request, data, policy, portForwardRepository),
  ),
  _OperationPolicy(
    'PUT',
    r'api/port-forwards/([^/]+)',
    'portForward',
    'update',
    targetResolver: (request, data, policy) =>
        _portForwardTarget(request, data, policy, portForwardRepository),
  ),
  _OperationPolicy(
    'DELETE',
    r'api/port-forwards/([^/]+)',
    'portForward',
    'delete',
    targetResolver: (request, data, policy) =>
        _portForwardTarget(request, data, policy, portForwardRepository),
  ),
  _OperationPolicy(
    'POST',
    r'api/port-forwards/([^/]+)/start',
    'portForward',
    'start',
    targetResolver: (request, data, policy) =>
        _portForwardTarget(request, data, policy, portForwardRepository),
  ),
  _OperationPolicy(
    'POST',
    r'api/port-forwards/([^/]+)/stop',
    'portForward',
    'stop',
    targetResolver: (request, data, policy) =>
        _portForwardTarget(request, data, policy, portForwardRepository),
  ),
  _OperationPolicy(
    'POST',
    r'api/secure-browser-tunnels',
    'secureBrowser',
    'createTunnel',
  ),
  _OperationPolicy(
    'DELETE',
    r'api/secure-browser-tunnels/([^/]+)',
    'secureBrowser',
    'stopTunnel',
  ),
  _OperationPolicy('POST', r'api/files/write', 'file', 'write'),
  _OperationPolicy('POST', r'api/files/delete', 'file', 'delete'),
  _OperationPolicy('POST', r'api/files/upload', 'file', 'upload'),
  _OperationPolicy('POST', r'api/files/rename', 'file', 'rename'),
  _OperationPolicy('POST', r'api/files/mkdir', 'file', 'mkdir'),
  _OperationPolicy('POST', r'api/files/chmod', 'file', 'chmod'),
  _OperationPolicy('POST', r'api/files/copy', 'file', 'copy'),
  _OperationPolicy('POST', r'api/files/extract', 'file', 'extract'),
  _OperationPolicy(
    'POST',
    r'api/docker/containers/([^/]+)/rename',
    'docker',
    'containerRename',
  ),
  _OperationPolicy(
    'DELETE',
    r'api/docker/containers/stopped',
    'docker',
    'containerRemoveStopped',
  ),
  _OperationPolicy(
    'DELETE',
    r'api/docker/containers/([^/]+)',
    'docker',
    'containerRemove',
  ),
  _OperationPolicy(
    'DELETE',
    r'api/docker/images/([^/]+)',
    'docker',
    'imageRemove',
  ),
  _OperationPolicy('POST', r'api/docker/networks', 'docker', 'networkCreate'),
  _OperationPolicy('POST', r'api/docker/volumes', 'docker', 'volumeCreate'),
  _OperationPolicy(
    'DELETE',
    r'api/docker/networks/([^/]+)',
    'docker',
    'networkRemove',
  ),
  _OperationPolicy(
    'DELETE',
    r'api/docker/volumes/([^/]+)',
    'docker',
    'volumeRemove',
  ),
  _OperationPolicy(
    'POST',
    r'api/docker/networks/([^/]+)/connect',
    'docker',
    'networkConnect',
  ),
  _OperationPolicy(
    'POST',
    r'api/docker/networks/([^/]+)/disconnect',
    'docker',
    'networkDisconnect',
  ),
  _OperationPolicy(
    'POST',
    r'api/docker/networks/prune',
    'docker',
    'networkPrune',
  ),
  _OperationPolicy(
    'POST',
    r'api/docker/volumes/prune',
    'docker',
    'volumePrune',
  ),
  _OperationPolicy('POST', r'api/docker/images/pull', 'docker', 'imagePull'),
  _OperationPolicy(
    'POST',
    r'api/docker/images/pull/stream',
    'docker',
    'imagePull',
  ),
  _OperationPolicy(
    'POST',
    r'api/docker/images/import',
    'docker',
    'imageImport',
  ),
  _OperationPolicy('POST', r'api/docker/images/tag', 'docker', 'imageTag'),
  _OperationPolicy('POST', r'api/docker/images/prune', 'docker', 'imagePrune'),
  _OperationPolicy(
    'POST',
    r'api/docker/compose/project/stream',
    'docker',
    'composeCreate',
  ),
  _OperationPolicy(
    'POST',
    r'api/docker/compose/project/up',
    'docker',
    'composeUp',
  ),
  _OperationPolicy(
    'POST',
    r'api/docker/compose/project/stop',
    'docker',
    'composeStop',
  ),
  _OperationPolicy(
    'POST',
    r'api/docker/compose/project/restart',
    'docker',
    'composeRestart',
  ),
  _OperationPolicy(
    'POST',
    r'api/docker/compose/project/down',
    'docker',
    'composeDown',
  ),
  _OperationPolicy(
    'POST',
    r'api/docker/build-cache/prune',
    'docker',
    'buildCachePrune',
  ),
  _OperationPolicy(
    'POST',
    r'api/docker/containers/([^/]+)/start',
    'docker',
    'containerStart',
  ),
  _OperationPolicy(
    'POST',
    r'api/docker/containers/([^/]+)/stop',
    'docker',
    'containerStop',
  ),
  _OperationPolicy(
    'POST',
    r'api/docker/containers/([^/]+)/restart',
    'docker',
    'containerRestart',
  ),
  _OperationPolicy(
    'POST',
    r'api/docker/containers/([^/]+)/pause',
    'docker',
    'containerPause',
  ),
  _OperationPolicy(
    'POST',
    r'api/docker/containers/([^/]+)/unpause',
    'docker',
    'containerUnpause',
  ),
  _OperationPolicy(
    'POST',
    r'api/docker/containers/([^/]+)/recreate',
    'docker',
    'containerRecreate',
  ),
  _OperationPolicy(
    'POST',
    r'api/docker/containers',
    'docker',
    'containerCreate',
  ),
  _OperationPolicy(
    'POST',
    r'api/docker/containers/batch-start',
    'docker',
    'containerBatchStart',
  ),
  _OperationPolicy(
    'POST',
    r'api/docker/containers/batch-stop',
    'docker',
    'containerBatchStop',
  ),
  _OperationPolicy('POST', r'api/cron-tasks', 'cron', 'create'),
  _OperationPolicy('PUT', r'api/cron-tasks/([^/]+)', 'cron', 'update'),
  _OperationPolicy('DELETE', r'api/cron-tasks/([^/]+)', 'cron', 'delete'),
  _OperationPolicy('POST', r'api/cron-tasks/([^/]+)/run', 'cron', 'run'),
  _OperationPolicy(
    'POST',
    r'api/cron-tasks/([^/]+)/history/sync',
    'cron',
    'syncHistory',
  ),
];
