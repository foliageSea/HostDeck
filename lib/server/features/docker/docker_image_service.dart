import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:logging/logging.dart';

import 'package:host_deck/server/core/ssh/ssh_session.dart';
import 'package:host_deck/server/features/docker/docker_engine_mapper.dart';
import 'package:host_deck/server/features/docker/docker_engine_repository.dart';
import 'package:host_deck/server/features/docker/docker_image.dart';
import 'package:host_deck/server/features/docker/docker_image_pull_progress.dart';

class DockerImagePullEvent {
  final String event;
  final Map<String, dynamic> data;

  const DockerImagePullEvent(this.event, this.data);
}

class DockerImageService {
  final DockerEngineRepository _engineRepository;
  final DockerEngineMapper _mapper;
  final _log = Logger('DockerImageService');

  DockerImageService(this._engineRepository, this._mapper);

  Future<List<DockerImage>> listImages(SshSession session) async {
    try {
      final usedImageIds = await _getUsedImageIds(session);
      final images = await _engineRepository.requestJsonList(
        session,
        method: 'GET',
        path: '/images/json',
        queryParameters: {'all': '1'},
      );

      return _mapper.mapImageSummaries(images, usedImageIds);
    } catch (e) {
      _log.severe('Failed to list images: $e');
      throw Exception('Failed to list images: $e');
    }
  }

  Future<void> removeImage(
    SshSession session,
    String imageId, {
    bool force = false,
  }) async {
    await _engineRepository.request(
      session,
      method: 'DELETE',
      path: '/images/${Uri.encodeComponent(imageId)}',
      queryParameters: {'force': force.toString()},
    );
  }

  Future<String> pullImage(SshSession session, String imageRef) async {
    final output = StringBuffer();
    await for (final event in pullImageStream(session, imageRef)) {
      if (event.event == 'progress') {
        output.writeln(jsonEncode(event.data));
      } else if (event.event == 'stderr') {
        output.write(event.data['text']?.toString() ?? '');
      } else if (event.event == 'error') {
        throw Exception(event.data['message']?.toString() ?? '拉取镜像失败');
      }
    }
    return output.toString().trim();
  }

  Stream<DockerImagePullEvent> pullImageStream(
    SshSession session,
    String imageRef,
  ) async* {
    final normalizedImage = imageRef.trim();
    if (normalizedImage.isEmpty) {
      throw ArgumentError('image is required');
    }

    final parsed = _splitImageReference(imageRef);
    var pending = '';
    int? statusCode;
    int? exitCode;
    String? responseMessage;

    await for (final event in _engineRepository.requestStream(
      session,
      method: 'POST',
      path: '/images/create',
      queryParameters: {
        'fromImage': parsed.repository,
        if (parsed.tag.isNotEmpty) 'tag': parsed.tag,
      },
    )) {
      if (event.completed) {
        statusCode = event.statusCode;
        exitCode = event.exitCode;
        continue;
      }

      if (event.source == DockerEngineStreamSource.stderr) {
        yield DockerImagePullEvent('stderr', {'text': event.text});
        continue;
      }

      pending += event.text;
      while (true) {
        final lineEnd = pending.indexOf('\n');
        if (lineEnd < 0) {
          break;
        }
        final line = pending.substring(0, lineEnd).trim();
        pending = pending.substring(lineEnd + 1);
        if (line.isEmpty) {
          continue;
        }

        final data = decodeDockerImagePullProgress(line);
        responseMessage = data['message']?.toString().trim().isNotEmpty == true
            ? data['message'].toString().trim()
            : responseMessage;
        final error = dockerImagePullError(data);
        if (error != null) {
          yield DockerImagePullEvent('error', {'message': error});
          return;
        }
        yield DockerImagePullEvent('progress', data);
      }
    }

    if (pending.trim().isNotEmpty) {
      final data = decodeDockerImagePullProgress(pending.trim());
      responseMessage = data['message']?.toString().trim().isNotEmpty == true
          ? data['message'].toString().trim()
          : responseMessage;
      final error = dockerImagePullError(data);
      if (error != null) {
        yield DockerImagePullEvent('error', {'message': error});
        return;
      }
      yield DockerImagePullEvent('progress', data);
    }

    if (statusCode == null || statusCode < 200 || statusCode >= 300) {
      yield DockerImagePullEvent('error', {
        'message':
            responseMessage ??
            'Docker Engine API request failed (${statusCode ?? 'unknown'})',
      });
      return;
    }
    if (exitCode != 0) {
      yield DockerImagePullEvent('error', {
        'message':
            'Docker Engine API command failed (${exitCode ?? 'unknown'})',
      });
      return;
    }

    yield DockerImagePullEvent('done', {'image': normalizedImage});
  }

  Future<String> importImage(
    SshSession session,
    Stream<List<int>> archive,
  ) async {
    final permit = await session.acquireOperation();
    SSHSession? process;
    StreamSubscription<Uint8List>? stdoutSubscription;
    StreamSubscription<Uint8List>? stderrSubscription;

    try {
      process = await session.client.execute(
        'sh -lc ${_shellQuote('docker load')}',
      );
    } catch (_) {
      permit.release();
      rethrow;
    }

    final stdoutBuffer = BytesBuilder(copy: false);
    final stderrBuffer = BytesBuilder(copy: false);
    final stdoutDone = Completer<void>();
    final stderrDone = Completer<void>();

    stdoutSubscription = process.stdout.listen(
      stdoutBuffer.add,
      onError: stdoutDone.completeError,
      onDone: stdoutDone.complete,
    );
    stderrSubscription = process.stderr.listen(
      stderrBuffer.add,
      onError: stderrDone.completeError,
      onDone: stderrDone.complete,
    );

    try {
      await process.stdin.addStream(
        archive.map(
          (chunk) => chunk is Uint8List ? chunk : Uint8List.fromList(chunk),
        ),
      );
      await process.stdin.close();
      await process.done;
      await stdoutDone.future;
      await stderrDone.future;

      final stdout = utf8.decode(
        stdoutBuffer.takeBytes(),
        allowMalformed: true,
      );
      final stderr = utf8.decode(
        stderrBuffer.takeBytes(),
        allowMalformed: true,
      );

      if (process.exitCode != null && process.exitCode != 0) {
        final output = [
          stderr.trim(),
          stdout.trim(),
        ].where((value) => value.isNotEmpty).join('\n');
        throw Exception(
          output.isNotEmpty
              ? output
              : 'docker load failed with exit code ${process.exitCode}',
        );
      }

      return [
        stdout.trim(),
        stderr.trim(),
      ].where((value) => value.isNotEmpty).join('\n');
    } catch (_) {
      process.close();
      rethrow;
    } finally {
      await stdoutSubscription.cancel();
      await stderrSubscription.cancel();
      permit.release();
    }
  }

  Future<void> tagImage(
    SshSession session,
    String sourceImage,
    String targetImage,
  ) async {
    final parsedTarget = _splitImageReference(targetImage);
    await _engineRepository.request(
      session,
      method: 'POST',
      path: '/images/${Uri.encodeComponent(sourceImage)}/tag',
      queryParameters: {
        'repo': parsedTarget.repository,
        if (parsedTarget.tag.isNotEmpty) 'tag': parsedTarget.tag,
      },
    );
  }

  Future<Stream<Uint8List>> exportImage(
    SshSession session,
    String imageRef,
  ) async {
    final normalizedImageRef = imageRef.trim();
    if (normalizedImageRef.isEmpty) {
      throw Exception('image is required');
    }

    await _engineRepository.requestJsonObject(
      session,
      method: 'GET',
      path: '/images/${Uri.encodeComponent(normalizedImageRef)}/json',
    );

    final command =
        'sh -lc ${_shellQuote('docker save ${_shellQuote(normalizedImageRef)}')}';
    final permit = await session.acquireOperation();
    final SSHSession process;
    try {
      process = await session.client.execute(command);
    } catch (_) {
      permit.release();
      rethrow;
    }

    final controller = StreamController<Uint8List>();
    final stderrBuffer = BytesBuilder(copy: false);
    StreamSubscription<Uint8List>? stdoutSubscription;
    StreamSubscription<Uint8List>? stderrSubscription;
    var released = false;

    void releaseOnce() {
      if (released) {
        return;
      }
      released = true;
      permit.release();
    }

    controller.onListen = () {
      stderrSubscription = process.stderr.listen((data) {
        if (stderrBuffer.length < 8192) {
          stderrBuffer.add(data);
        }
      });

      stdoutSubscription = process.stdout.listen(
        controller.add,
        onError: (Object error, StackTrace stackTrace) async {
          controller.addError(error, stackTrace);
          releaseOnce();
          await controller.close();
        },
        onDone: () async {
          try {
            await process.done;
            await stderrSubscription?.cancel();

            if (process.exitCode != null && process.exitCode != 0) {
              final stderr = utf8.decode(
                stderrBuffer.takeBytes(),
                allowMalformed: true,
              );
              controller.addError(
                Exception(
                  stderr.trim().isEmpty
                      ? 'docker save failed with exit code ${process.exitCode}'
                      : stderr.trim(),
                ),
              );
            }
          } finally {
            releaseOnce();
          }

          await controller.close();
        },
      );
    };

    controller.onCancel = () async {
      await stdoutSubscription?.cancel();
      await stderrSubscription?.cancel();
      process.close();
      releaseOnce();
    };

    return controller.stream;
  }

  Future<List<Map<String, dynamic>>> getImageHistory(
    SshSession session,
    String imageId,
  ) async {
    final items = await _engineRepository.requestJsonList(
      session,
      method: 'GET',
      path: '/images/${Uri.encodeComponent(imageId)}/history',
    );

    return items
        .whereType<Map>()
        .map(
          (item) =>
              _mapper.mapImageHistoryItem(Map<String, dynamic>.from(item)),
        )
        .toList();
  }

  Future<Map<String, dynamic>> getImageCreateDefaults(
    SshSession session,
    String imageId,
  ) async {
    final detail = await _engineRepository.requestJsonObject(
      session,
      method: 'GET',
      path: '/images/${Uri.encodeComponent(imageId)}/json',
    );
    return _mapper.mapImageCreateDefaults(detail);
  }

  Future<List<Map<String, dynamic>>> getImageContainers(
    SshSession session,
    String imageId,
  ) async {
    final filters = jsonEncode({
      'ancestor': [imageId],
    });
    final containers = await _engineRepository.requestJsonList(
      session,
      method: 'GET',
      path: '/containers/json',
      queryParameters: {'all': '1', 'filters': filters},
    );

    return containers.whereType<Map>().map((item) {
      final json = Map<String, dynamic>.from(item);
      final names =
          (json['Names'] as List?)
              ?.map((name) => name.toString())
              .where((name) => name.isNotEmpty)
              .toList() ??
          <String>[];
      return <String, dynamic>{
        'id': (json['Id'] ?? '').toString(),
        'name': names.isEmpty ? '' : _normalizeContainerName(names.first),
        'image': (json['Image'] ?? '').toString(),
        'state': (json['State'] ?? '').toString(),
        'status': (json['Status'] ?? '').toString(),
      };
    }).toList();
  }

  Future<String> pruneImages(
    SshSession session, {
    bool includeUnused = false,
  }) async {
    final filters = includeUnused
        ? jsonEncode(<String, List<String>>{})
        : jsonEncode({
            'dangling': ['true'],
          });
    return await _engineRepository.requestText(
      session,
      method: 'POST',
      path: '/images/prune',
      queryParameters: {'filters': filters},
    );
  }

  Future<Set<String>> _getUsedImageIds(SshSession session) async {
    try {
      final containers = await _engineRepository.requestJsonList(
        session,
        method: 'GET',
        path: '/containers/json',
        queryParameters: {'all': '1'},
      );

      return containers
          .whereType<Map>()
          .map((item) => (item['ImageID'] ?? item['ImageId'] ?? '').toString())
          .where((id) => id.isNotEmpty)
          .toSet();
    } catch (_) {
      return <String>{};
    }
  }

  String _shellQuote(String value) {
    return "'${value.replaceAll("'", "'\\''")}'";
  }

  String _normalizeContainerName(String value) {
    if (value.startsWith('/')) {
      return value.substring(1);
    }
    return value;
  }

  _ImageReference _splitImageReference(String imageRef) {
    final value = imageRef.trim();
    final digestIndex = value.indexOf('@');
    if (digestIndex >= 0) {
      return _ImageReference(value, '');
    }

    final lastSlash = value.lastIndexOf('/');
    final lastColon = value.lastIndexOf(':');
    if (lastColon > lastSlash) {
      return _ImageReference(
        value.substring(0, lastColon),
        value.substring(lastColon + 1),
      );
    }

    return _ImageReference(value, 'latest');
  }
}

class _ImageReference {
  final String repository;
  final String tag;

  const _ImageReference(this.repository, this.tag);
}
