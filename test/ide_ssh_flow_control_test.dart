import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
// Exercise the actual receive-window implementation used by the IDE tunnel.
// ignore: implementation_imports
import 'package:dartssh2/src/message/msg_channel.dart';
// ignore: implementation_imports
import 'package:dartssh2/src/ssh_channel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const windowSize = 2 * 1024 * 1024;
  const packetSize = 32 * 1024;

  for (final subscribeLate in [false, true]) {
    test(
      'IDE SSH tunnel replenishes an exhausted window after '
      '${subscribeLate ? 'its first listener' : 'a slow reader resumes'}',
      () async {
        final adjustments = <int>[];
        final controller = SSHChannelController(
          localId: 0,
          localMaximumPacketSize: packetSize,
          localInitialWindowSize: windowSize,
          remoteId: 1,
          remoteMaximumPacketSize: packetSize,
          remoteInitialWindowSize: windowSize,
          sendMessage: (message) {
            if (message is SSH_Message_Channel_Window_Adjust) {
              adjustments.add(message.bytesToAdd);
            }
          },
        );
        final channel = SSHForwardChannel(controller.channel);
        StreamSubscription<List<int>>? subscription;
        var received = 0;
        void listen() {
          // Preserve the map/cast chain used by LoopbackSshBridge.
          subscription = channel.stream.cast<List<int>>().listen((bytes) {
            received += bytes.length;
          });
        }

        try {
          if (!subscribeLate) {
            listen();
            subscription!.pause();
          }
          for (var offset = 0; offset < windowSize; offset += packetSize) {
            controller.handleMessage(
              SSH_Message_Channel_Data(
                recipientChannel: 0,
                data: Uint8List(packetSize),
              ),
            );
          }
          expect(adjustments, isEmpty);
          if (subscribeLate) {
            listen();
          } else {
            subscription!.resume();
          }
          await Future<void>.delayed(Duration.zero);
          expect(received, windowSize);
          expect(adjustments.fold<int>(0, (sum, n) => sum + n), windowSize);

          // The same channel must keep delivering beyond the first window.
          controller.handleMessage(
            SSH_Message_Channel_Data(
              recipientChannel: 0,
              data: Uint8List(packetSize),
            ),
          );
          await Future<void>.delayed(Duration.zero);
          expect(received, windowSize + packetSize);
        } finally {
          await subscription?.cancel();
          channel.destroy();
        }
      },
    );
  }
}
