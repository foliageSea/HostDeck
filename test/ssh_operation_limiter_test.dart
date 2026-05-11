import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ssh_tool/server/models/ssh_operation_limiter.dart';

void main() {
  test('queues operations beyond concurrency limit', () async {
    final limiter = SshOperationLimiter(maxConcurrentOperations: 1);
    final firstStarted = Completer<void>();
    final releaseFirst = Completer<void>();
    final secondStarted = Completer<void>();

    final first = limiter.run(() async {
      firstStarted.complete();
      await releaseFirst.future;
      return 'first';
    });
    await firstStarted.future;

    final second = limiter.run(() async {
      secondStarted.complete();
      return 'second';
    });
    await Future<void>.delayed(Duration.zero);

    expect(limiter.runningOperations, 1);
    expect(limiter.queuedOperations, 1);
    expect(secondStarted.isCompleted, isFalse);

    releaseFirst.complete();

    expect(await first, 'first');
    expect(await second, 'second');
    expect(limiter.runningOperations, 0);
    expect(limiter.queuedOperations, 0);
  });

  test('releases permit when operation throws', () async {
    final limiter = SshOperationLimiter(maxConcurrentOperations: 1);

    await expectLater(
      limiter.run<void>(() async => throw StateError('boom')),
      throwsStateError,
    );

    expect(limiter.runningOperations, 0);
    expect(limiter.queuedOperations, 0);
    expect(await limiter.run(() async => 1), 1);
  });
}
