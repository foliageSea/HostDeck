import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:host_deck_sidecar/protocol.dart';

import 'package:host_deck_sidecar/src/file_operations.dart';
import 'package:host_deck_sidecar/src/stdio_command.dart';

const _usage = '''
Usage: hostdeck-file-sidecar <copy|move|compress|extract> <source> <target>
       hostdeck-file-sidecar run --stdio
       hostdeck-file-sidecar --version [--json]
The target must not exist, and its parent directory must exist.
''';

Future<void> main(List<String> args) async {
  if (args.length == 1 && (args[0] == '--help' || args[0] == '-h')) {
    stdout.write(_usage);
    return;
  }
  if (args.isNotEmpty && args[0] == '--version') {
    if (args.length == 1) {
      stdout.writeln(sidecarVersion);
      return;
    }
    if (args.length == 2 && args[1] == '--json') {
      stdout.writeln(
        jsonEncode({
          'version': sidecarVersion,
          'protocol': sidecarProtocolVersion,
        }),
      );
      return;
    }
  }
  final stdioMode =
      args.length == 2 && args[0] == 'run' && args[1] == '--stdio';
  final operation = args.isEmpty
      ? null
      : SidecarOperation.values
            .where((candidate) => candidate.name == args[0])
            .firstOrNull;
  if (!stdioMode &&
      (operation == null ||
          args.length != 3 ||
          !validSidecarPath(args[1]) ||
          !validSidecarPath(args[2]))) {
    stderr.write(_usage);
    exitCode = 2;
    return;
  }

  final cancellation = SidecarCancellation();
  final signals = <StreamSubscription<ProcessSignal>>[
    ProcessSignal.sigint.watch().listen((_) => cancellation.cancel()),
    if (!Platform.isWindows)
      ProcessSignal.sigterm.watch().listen((_) => cancellation.cancel()),
  ];
  try {
    if (stdioMode) {
      exitCode = await runSidecarStdio(
        input: stdin,
        writeFrame: (frame) => stdout.add(encodeSidecarFrame(frame)),
        runOperation: runFileOperation,
        cancellation: cancellation,
      );
      await stdout.flush();
    } else {
      exitCode = await _runInteractive(
        operation!,
        args[1],
        args[2],
        cancellation,
      );
    }
  } finally {
    for (final subscription in signals) {
      await subscription.cancel();
    }
  }
}

Future<int> _runInteractive(
  SidecarOperation operation,
  String sourcePath,
  String targetPath,
  SidecarCancellation cancellation,
) async {
  final progress = SidecarProgressEmitter((event) {
    final total = event.bytesTotal;
    final entries = event.entriesTotal;
    stderr.writeln(
      '${event.phase.name}: ${event.bytesDone}${total == null ? '' : '/$total'} bytes, '
      '${event.entriesDone}${entries == null ? '' : '/$entries'} entries',
    );
  });
  try {
    await runFileOperation(
      operation: operation,
      sourcePath: sourcePath,
      targetPath: targetPath,
      cancellation: cancellation,
      onProgress: progress.add,
    );
    progress.flush();
    stdout.writeln('OK');
    return 0;
  } on SidecarCancelled {
    progress.flush();
    stderr.writeln('Cancelled.');
    return 130;
  } catch (error) {
    progress.flush();
    stderr.writeln(shortSidecarError(error));
    return 1;
  }
}
