import 'dart:async';
import 'dart:convert';

import 'package:host_deck_sidecar/protocol.dart';
import 'package:test/test.dart';

import 'package:host_deck_sidecar/src/stdio_command.dart';

const _request = {
  'v': 1,
  'type': 'run',
  'id': 'item_1',
  'operation': 'copy',
  'sourcePath': '/目录/源\n名',
  'targetPath': '/目录/目标',
};

void main() {
  test('round trips consecutive and UTF-8 fragmented frames', () async {
    final first = encodeSidecarFrame(_request);
    final second = encodeSidecarFrame({'v': 1, 'type': 'ping', 'id': 'item_1'});
    final decoded = await decodeSidecarFrames(
      Stream.fromIterable([
        for (final byte in first.take(first.length - 1)) [byte],
        [first.last, ...second],
      ]),
    ).toList();
    expect(decoded, [
      _request,
      {'v': 1, 'type': 'ping', 'id': 'item_1'},
    ]);
  });

  test(
    'rejects incomplete, oversized, malformed, and nonobject frames',
    () async {
      for (final bytes in [
        utf8.encode('{}'),
        List.filled(sidecarMaxFrameBytes + 1, 65),
        [255, 10],
        utf8.encode('[]\n'),
      ]) {
        await expectLater(
          decodeSidecarFrames(Stream.value(bytes)),
          emitsError(isA<FormatException>()),
        );
      }
    },
  );

  test('validates counters and unknown totals', () {
    const progress = SidecarProgress(
      phase: SidecarPhase.working,
      bytesDone: 10,
    );
    expect(
      SidecarProgress.fromJson(progress.toJson()).toJson(),
      progress.toJson(),
    );
    expect(
      () => SidecarProgress.fromJson({...progress.toJson(), 'bytesTotal': 2}),
      throwsFormatException,
    );
  });

  test('emits progress, heartbeat, and confirmed cancellation', () async {
    final input = StreamController<List<int>>();
    final messages = <Map<String, Object?>>[];
    final heartbeatSeen = Completer<void>();
    final allowOperationToFinish = Completer<void>();
    final cancellation = SidecarCancellation();
    final exit = runSidecarStdio(
      input: input.stream,
      cancellation: cancellation,
      heartbeatInterval: const Duration(milliseconds: 10),
      writeFrame: (frame) {
        messages.add(frame);
        if (frame['type'] == 'heartbeat' && !heartbeatSeen.isCompleted) {
          heartbeatSeen.complete();
        }
      },
      runOperation:
          ({
            required operation,
            required sourcePath,
            required targetPath,
            required cancellation,
            required onProgress,
          }) async {
            expect(operation, SidecarOperation.copy);
            expect(sourcePath, _request['sourcePath']);
            onProgress(
              const SidecarProgress(
                phase: SidecarPhase.working,
                bytesDone: 6,
                bytesTotal: 10,
              ),
            );
            await allowOperationToFinish.future;
            cancellation.throwIfCancelled();
          },
    );
    input.add(encodeSidecarFrame(_request));
    await heartbeatSeen.future.timeout(const Duration(seconds: 2));
    input.add(encodeSidecarFrame({'v': 1, 'type': 'cancel', 'id': 'item_1'}));
    await input.close();
    allowOperationToFinish.complete();
    expect(await exit.timeout(const Duration(seconds: 2)), 130);
    expect(
      messages.where((frame) => frame['type'] == 'progress').single['progress'],
      containsPair('bytesDone', 6),
    );
    expect(
      messages.where((frame) => frame['type'] == 'result').single['status'],
      'cancelled',
    );
  });

  test(
    'malformed control fails the protocol, not the user operation',
    () async {
      final input = StreamController<List<int>>();
      final ready = Completer<void>();
      final finish = Completer<void>();
      final messages = <Map<String, Object?>>[];
      final exit = runSidecarStdio(
        input: input.stream,
        cancellation: SidecarCancellation(),
        writeFrame: messages.add,
        runOperation:
            ({
              required operation,
              required sourcePath,
              required targetPath,
              required cancellation,
              required onProgress,
            }) async {
              ready.complete();
              await finish.future;
              cancellation.throwIfCancelled();
            },
      );
      input.add(encodeSidecarFrame(_request));
      await ready.future.timeout(const Duration(seconds: 2));
      input.add(encodeSidecarFrame({'v': 1, 'type': 'cancel', 'id': 'wrong'}));
      await input.close();
      finish.complete();
      expect(await exit.timeout(const Duration(seconds: 2)), 2);
      expect(messages.last, containsPair('errorCode', 'protocol_error'));
    },
  );
}
