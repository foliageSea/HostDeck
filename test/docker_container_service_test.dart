import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:host_deck/server/features/docker/docker_container_service.dart';
import 'package:host_deck/server/features/docker/docker_engine_mapper.dart';
import 'package:host_deck/server/features/docker/docker_engine_repository.dart';

void main() {
  group('DockerContainerService logs decoding', () {
    final service = DockerContainerService(
      DockerEngineRepository(),
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

    test('streams multiplexed frames split across chunks', () async {
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
      final chunks = <Uint8List>[
        Uint8List.sublistView(bytes, 0, 3),
        Uint8List.sublistView(bytes, 3, 11),
        Uint8List.sublistView(bytes, 11, 19),
        Uint8List.sublistView(bytes, 19),
      ];

      final events = await service
          .decodeDockerLogStream(Stream.fromIterable(chunks), multiplexed: true)
          .toList();

      expect(events.map((event) => event.event), ['stdout', 'stderr']);
      expect(events.map((event) => event.text), ['hello\n', 'error\n']);
    });

    test('preserves utf8 characters split across raw chunks', () async {
      final bytes = Uint8List.fromList(utf8.encode('日志输出'));
      final chunks = <Uint8List>[
        Uint8List.sublistView(bytes, 0, 1),
        Uint8List.sublistView(bytes, 1, 4),
        Uint8List.sublistView(bytes, 4),
      ];

      final events = await service
          .decodeDockerLogStream(
            Stream.fromIterable(chunks),
            multiplexed: false,
          )
          .toList();

      expect(events.map((event) => event.text).join(), '日志输出');
    });

    test('rejects an incomplete multiplexed frame', () async {
      final stream = service.decodeDockerLogStream(
        Stream.value(Uint8List.fromList([1, 0, 0, 0, 0, 0, 0, 4, 65])),
        multiplexed: true,
      );

      await expectLater(stream.toList(), throwsA(isA<FormatException>()));
    });
  });
}
