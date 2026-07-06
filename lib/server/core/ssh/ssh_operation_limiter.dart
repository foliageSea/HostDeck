import 'dart:async';
import 'dart:collection';

class SshOperationLimiter {
  final int maxConcurrentOperations;
  final Queue<Completer<SshOperationPermit>> _waitQueue = Queue();
  int _runningOperations = 0;

  SshOperationLimiter({required this.maxConcurrentOperations}) {
    if (maxConcurrentOperations <= 0) {
      throw ArgumentError.value(
        maxConcurrentOperations,
        'maxConcurrentOperations',
        'Must be greater than zero',
      );
    }
  }

  int get runningOperations => _runningOperations;
  int get queuedOperations => _waitQueue.length;

  Future<SshOperationPermit> acquire() {
    if (_runningOperations < maxConcurrentOperations) {
      _runningOperations++;
      return Future.value(SshOperationPermit._(this));
    }

    final completer = Completer<SshOperationPermit>();
    _waitQueue.add(completer);
    return completer.future;
  }

  Future<T> run<T>(FutureOr<T> Function() action) async {
    final permit = await acquire();
    try {
      return await action();
    } finally {
      permit.release();
    }
  }

  Map<String, int> snapshot() {
    return {
      'maxConcurrentOperations': maxConcurrentOperations,
      'runningOperations': runningOperations,
      'queuedOperations': queuedOperations,
    };
  }

  void _release() {
    if (_waitQueue.isNotEmpty) {
      _waitQueue.removeFirst().complete(SshOperationPermit._(this));
      return;
    }

    if (_runningOperations > 0) {
      _runningOperations--;
    }
  }
}

class SshOperationPermit {
  final SshOperationLimiter _limiter;
  bool _released = false;

  SshOperationPermit._(this._limiter);

  void release() {
    if (_released) {
      return;
    }

    _released = true;
    _limiter._release();
  }
}
