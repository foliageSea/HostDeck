import 'dart:async';

import 'package:dartssh2/dartssh2.dart';

import 'package:host_deck/server/core/ssh/ssh_operation_limiter.dart';

abstract interface class SshOperationContext {
  SSHClient get client;

  Future<SshOperationPermit> acquireOperation();

  Future<T> runOperation<T>(FutureOr<T> Function() action);
}

class SshConnectionHandle implements SshOperationContext {
  final String connectionId;
  @override
  final SSHClient client;
  final SshOperationLimiter operationLimiter;

  const SshConnectionHandle({
    required this.connectionId,
    required this.client,
    required this.operationLimiter,
  });

  @override
  Future<SshOperationPermit> acquireOperation() => operationLimiter.acquire();

  @override
  Future<T> runOperation<T>(FutureOr<T> Function() action) =>
      operationLimiter.run(action);
}
