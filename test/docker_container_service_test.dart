import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:host_deck/server/core/ssh/ssh_repository.dart';
import 'package:host_deck/server/features/docker/docker_container_service.dart';
import 'package:host_deck/server/features/docker/docker_engine_mapper.dart';
import 'package:host_deck/server/features/docker/docker_engine_repository.dart';

void main() {
  group('DockerContainerService logs decoding', () {
    final service = DockerContainerService(
      DockerEngineRepository(SshRepository()),
      DockerEngineMapper(),
    );

    test('returns plain utf8 logs when stream is not multiplexed', () {
      final result = service.debugDecodeDockerLogs(
        Uint8List.fromList('plain log output'.codeUnits),
      );

      expect(result, 'plain log output');
    });

    test('decodes docker multiplexed stdout and stderr frames', () {
      final bytes = Uint8List.fromList([
        1,
        0,
        0,
        0,
        0,
        0,
        0,
        6,
        ...'hello\n'.codeUnits,
        2,
        0,
        0,
        0,
        0,
        0,
        0,
        6,
        ...'error\n'.codeUnits,
      ]);

      final result = service.debugDecodeDockerLogs(bytes);
      expect(result, 'hello\nerror\n');
    });
  });
}
