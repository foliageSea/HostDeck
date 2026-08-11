import 'dart:async';
import 'dart:io';

import 'package:logging/logging.dart';

void registerServerShutdownHandlers({
  required Logger log,
  required Future<void> Function() stopServer,
  required Future<void> Function() closeLogging,
}) {
  final signals = <ProcessSignal>[ProcessSignal.sigint];
  if (!Platform.isWindows) {
    signals.add(ProcessSignal.sigterm);
  }

  final subscriptions = <StreamSubscription<ProcessSignal>>[];
  var isStopping = false;
  for (final signal in signals) {
    try {
      subscriptions.add(
        signal.watch().listen((_) async {
          if (isStopping) return;
          isStopping = true;
          log.info('Received ${signal.name}, shutting down...');
          await stopServer();
          for (final subscription in subscriptions) {
            await subscription.cancel();
          }
          await closeLogging();
          exit(0);
        }),
      );
    } on SignalException {
      log.warning('Signal ${signal.name} is not supported on this platform.');
    }
  }
}
