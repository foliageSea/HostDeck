import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:logging/logging.dart';
import 'package:mime/mime.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_multipart/shelf_multipart.dart';

import 'package:host_deck/server/core/http/result.dart';
import 'package:host_deck/server/core/http/server_sent_event.dart';
import 'package:host_deck/server/core/ssh/shared_ssh_session_resolver.dart';
import 'package:host_deck/server/core/ssh/ssh_service.dart';
import 'package:host_deck/server/core/ssh/ssh_session.dart';
import 'package:host_deck/server/features/files/file_error.dart';
import 'package:host_deck/server/features/files/file_service.dart';
import 'package:host_deck/server/features/files/file_task.dart';
import 'package:host_deck/server/features/files/file_task_manager.dart';

class FileController {
  final _log = Logger('FileController');
  final FileService _fileService;
  final FileTaskManager _taskManager;
  final SharedSshSessionResolver _sessionResolver;

  FileController(SshService sshService, this._fileService, this._taskManager)
    : _sessionResolver = SharedSshSessionResolver(
        sshService,
        type: SharedSshSessionType.sftp,
        purpose: SshSessionPurpose.fileManagement,
      );

  Future<SshSession> _resolveSession(Request request) async {
    return _sessionResolver.resolveFromRequest(request);
  }

  Response _sessionErrorResponse(Object error) {
    return _sessionResolver.errorResponse(error);
  }

  Future<Response> createTask(Request request) async {
    try {
      final connectionId = request.url.queryParameters['connectionId'];
      if (connectionId == null || connectionId.isEmpty) {
        return Result.fail(400, 'Missing connectionId');
      }
      final data =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final type = FileTaskType.values.byName(data['type'] as String);
      final rawItems = data['items'];
      if (rawItems is! List) {
        return Result.fail(400, 'items is required');
      }
      final items = rawItems.map((item) {
        if (item is! Map) throw ArgumentError('Invalid task item');
        final sourcePath = item['sourcePath'];
        final targetPath = item['targetPath'];
        bool valid(Object? path) =>
            path is String &&
            path.isNotEmpty &&
            !path.contains(String.fromCharCode(0));
        if (!valid(sourcePath) ||
            (type != FileTaskType.delete && !valid(targetPath))) {
          throw ArgumentError('Invalid task path');
        }
        return {
          'sourcePath': sourcePath as String,
          'targetPath': type == FileTaskType.delete
              ? null
              : targetPath as String,
        };
      }).toList();
      return Result.ok(_taskManager.create(connectionId, type, items).toJson());
    } on ArgumentError catch (error) {
      return Result.fail(400, error.message?.toString() ?? error.toString());
    } catch (error) {
      return Result.fail(500, error.toString());
    }
  }

  Response listTasks(Request request) {
    final connectionId = request.url.queryParameters['connectionId'];
    final limit =
        int.tryParse(request.url.queryParameters['limit'] ?? '') ?? 100;
    return Result.ok(
      _taskManager
          .list(connectionId: connectionId, limit: limit)
          .map((task) => task.toJson())
          .toList(),
    );
  }

  Response getTask(Request request, String id) {
    final task = _taskManager.find(id);
    return task == null
        ? Result.fail(404, 'Task not found')
        : Result.ok(task.toJson());
  }

  Future<Response> cancelTask(Request request, String id) async {
    final task = await _taskManager.cancel(id);
    return task == null
        ? Result.fail(404, 'Task not found')
        : Result.ok(task.toJson());
  }

  Response streamTask(Request request, String id) {
    if (_taskManager.find(id) == null) {
      return Result.fail(404, 'Task not found');
    }
    final stream = _taskManager.watch(id).map((task) {
      final event =
          task.status == FileTaskStatus.success ||
              task.status == FileTaskStatus.failed ||
              task.status == FileTaskStatus.cancelled
          ? 'done'
          : 'task';
      return encodeServerSentEvent(event, task.toJson());
    });
    return Response.ok(
      stream,
      headers: {
        'content-type': 'text/event-stream; charset=utf-8',
        'cache-control': 'no-cache, no-transform',
        'x-accel-buffering': 'no',
      },
    );
  }

  Future<Response> createSession(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final connectionId = data['connectionId'];

      if (connectionId == null) {
        return Result.fail(400, 'Missing connectionId');
      }

      final session = await _sessionResolver.createForConnection(
        connectionId.toString(),
      );

      return Result.ok({'sessionId': session.id});
    } on SshSessionLimitExceeded catch (e) {
      return Result.fail(429, '最多只能创建 ${e.maxSessions} 个 SSH 会话。');
    } catch (e) {
      return Result.fail(500, e.toString());
    }
  }

  Future<Response> closeSession(Request request) async {
    try {
      await _sessionResolver.closeFromRequest(request);

      return Result.ok('Session closed');
    } catch (e) {
      return Result.fail(500, e.toString());
    }
  }

  Future<Response> listFiles(Request request) async {
    final path = request.url.queryParameters['path'] ?? '.';

    late final SshSession session;
    try {
      session = await _resolveSession(request);
    } catch (error) {
      return _sessionErrorResponse(error);
    }

    try {
      final items = await _fileService.listFiles(session, path);
      // Convert DateTime to ISO string for JSON
      final jsonItems = items
          .map(
            (item) => {
              'filename': item.filename,
              'longname': item.longname,
              'isDirectory': item.isDirectory,
              'size': item.size,
              'modifyTime': item.mtime?.toIso8601String(),
            },
          )
          .toList();
      return Result.ok(jsonItems);
    } catch (e) {
      return Result.fail(500, describeFileOperationError(e));
    }
  }

  Future<Response> directorySize(Request request) async {
    final path = request.url.queryParameters['path'];
    if (path == null || path.trim().isEmpty) {
      return Result.fail(400, 'Missing path');
    }

    late final SshSession session;
    try {
      session = await _resolveSession(request);
    } catch (error) {
      return _sessionErrorResponse(error);
    }

    try {
      final size = await _fileService.getDirectorySize(session, path);
      return Result.ok({'size': size});
    } catch (e) {
      return Result.fail(500, describeFileOperationError(e));
    }
  }

  Future<Response> readFile(Request request) async {
    final path = request.url.queryParameters['path'];
    final download = request.url.queryParameters['download'] == 'true';

    if (path == null) {
      return Response.badRequest(body: 'Missing path');
    }

    late final SshSession session;
    try {
      session = await _resolveSession(request);
    } catch (error) {
      if (error is ArgumentError) {
        return Response.badRequest(
          body: error.message?.toString() ?? error.toString(),
        );
      }

      if (error is StateError) {
        return Response.notFound(error.message);
      }

      return Response.internalServerError(body: error.toString());
    }

    try {
      final stream = await _fileService.readFileStream(session, path);

      final headers = <String, Object>{
        'content-type': 'application/octet-stream',
      };

      if (download) {
        final filename = path.split('/').last;
        final encodedFilename = Uri.encodeComponent(filename);
        headers['content-disposition'] =
            "attachment; filename*=UTF-8''$encodedFilename";
      }

      return Response.ok(stream, headers: headers);
    } catch (e) {
      return Response.internalServerError(body: describeFileOperationError(e));
    }
  }

  Future<Response> writeFile(Request request) async {
    final path = request.url.queryParameters['path'];
    if (path == null) {
      return Result.fail(400, 'Missing path');
    }

    late final SshSession session;
    try {
      session = await _resolveSession(request);
    } catch (error) {
      return _sessionErrorResponse(error);
    }

    try {
      await _fileService.writeFileStream(session, path, request.read());
      return Result.ok('File written');
    } catch (e) {
      return Result.fail(500, describeFileOperationError(e));
    }
  }

  Future<Response> uploadFile(Request request) async {
    final path = request.url.queryParameters['path'];
    if (path == null) {
      return Result.fail(400, 'Missing path');
    }

    late final SshSession session;
    try {
      session = await _resolveSession(request);
    } catch (error) {
      return _sessionErrorResponse(error);
    }

    Response? failure;
    var uploaded = false;
    try {
      final multipart = request.multipart();
      if (multipart == null) {
        return Result.fail(400, 'Expected multipart request');
      }
      await for (final part in multipart.parts) {
        if (failure != null) {
          await part.drain<void>();
          continue;
        }
        final contentDisposition = part.headers['content-disposition'];
        final filename = contentDisposition == null
            ? null
            : HeaderValue.parse(contentDisposition).parameters['filename'];
        if (filename == null) {
          await part.drain<void>();
          continue;
        }
        if (filename.isEmpty ||
            filename == '.' ||
            filename == '..' ||
            filename.contains('/') ||
            filename.contains(String.fromCharCode(92)) ||
            filename.contains(String.fromCharCode(0))) {
          failure = Result.fail(400, '上传文件名无效。');
          await part.drain<void>();
          continue;
        }

        final target = path.endsWith('/')
            ? '$path$filename'
            : '$path/$filename';
        // Keep ownership of the multipart subscription. SFTP can cancel its
        // stream before it has read the part, e.g. if opening the remote file
        // fails or a write is rejected. Drain the remainder before replying
        // so HTTP proxies and the browser can receive the JSON error.
        final input = StreamIterator<List<int>>(part);
        try {
          await _fileService.writeFileStream(
            session,
            target,
            _uploadPart(input),
          );
          uploaded = true;
        } catch (error) {
          final status = switch (error) {
            SftpStatusError(code: SftpErrorCode.permissionDenied) => 403,
            SftpStatusError(code: SftpErrorCode.noSuchFile) => 404,
            _ => 500,
          };
          final remoteStatus = error is SftpStatusError
              ? ' (SFTP code ${error.code})'
              : '';
          _log.warning('文件上传失败：${error.runtimeType}$remoteStatus');
          failure = Result.fail(status, describeFileOperationError(error));
          while (await input.moveNext()) {
            // Discard in chunks; do not retain the rest of the request.
          }
        } finally {
          await input.cancel();
        }
      }
      return failure ??
          (uploaded
              ? Result.ok('Upload complete')
              : Result.fail(400, '请求未包含文件。'));
    } on FormatException {
      return failure ?? Result.fail(400, '上传请求格式无效。');
    } on MimeMultipartException {
      return failure ?? Result.fail(400, '上传请求不完整。');
    } catch (error) {
      return failure ?? Result.fail(500, describeFileOperationError(error));
    }
  }

  Stream<List<int>> _uploadPart(StreamIterator<List<int>> input) async* {
    while (await input.moveNext()) {
      yield input.current;
    }
  }

  Future<Response> batchDownload(Request request) async {
    late final SshSession session;
    try {
      session = await _resolveSession(request);
    } catch (error) {
      if (error is ArgumentError) {
        return Response.badRequest(
          body: error.message?.toString() ?? error.toString(),
        );
      }

      if (error is StateError) {
        return Response.notFound(error.message);
      }

      return Response.internalServerError(body: error.toString());
    }

    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final paths = (data['paths'] as List).cast<String>();

      final stream = await _fileService.downloadBatch(session, paths);
      return Response.ok(
        stream,
        headers: {
          'content-type': 'application/gzip',
          'content-disposition': 'attachment; filename="download.tar.gz"',
        },
      );
    } catch (e) {
      return Response.internalServerError(body: describeFileOperationError(e));
    }
  }

  Future<Response> rename(Request request) async {
    late final SshSession session;
    try {
      session = await _resolveSession(request);
    } catch (error) {
      return _sessionErrorResponse(error);
    }

    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final oldPath = data['oldPath'] as String;
      final newPath = data['newPath'] as String;

      await _fileService.rename(session, oldPath, newPath);
      return Result.ok('Renamed');
    } catch (e) {
      return Result.fail(500, describeFileOperationError(e));
    }
  }

  Future<Response> mkdir(Request request) async {
    late final SshSession session;
    try {
      session = await _resolveSession(request);
    } catch (error) {
      return _sessionErrorResponse(error);
    }

    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final path = data['path'] as String;

      await _fileService.mkdir(session, path);
      return Result.ok('Directory created');
    } catch (e) {
      return Result.fail(500, describeFileOperationError(e));
    }
  }

  Future<Response> chmod(Request request) async {
    late final SshSession session;
    try {
      session = await _resolveSession(request);
    } catch (error) {
      return _sessionErrorResponse(error);
    }

    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final path = data['path']?.toString().trim() ?? '';
      final mode = data['mode']?.toString().trim() ?? '';
      final recursive = data['recursive'] == true;

      if (path.isEmpty || mode.isEmpty) {
        return Result.fail(400, 'Missing path or mode');
      }

      await _fileService.chmod(session, path, mode, recursive: recursive);
      return Result.ok('Permission changed');
    } on ArgumentError catch (e) {
      return Result.fail(400, e.message?.toString() ?? e.toString());
    } catch (e) {
      return Result.fail(500, describeFileOperationError(e));
    }
  }

  Future<Response> copy(Request request) async {
    late final SshSession session;
    try {
      session = await _resolveSession(request);
    } catch (error) {
      return _sessionErrorResponse(error);
    }

    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final source = data['source'] as String;
      final target = data['target'] as String;

      await _fileService.copy(session, source, target);
      return Result.ok('Copied');
    } catch (e) {
      return Result.fail(500, describeFileOperationError(e));
    }
  }

  Future<Response> extract(Request request) async {
    late final SshSession session;
    try {
      session = await _resolveSession(request);
    } catch (error) {
      return _sessionErrorResponse(error);
    }

    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final archivePath = data['archivePath']?.toString().trim() ?? '';
      final targetPath = data['targetPath']?.toString().trim() ?? '';

      if (archivePath.isEmpty || targetPath.isEmpty) {
        return Result.fail(400, 'Missing archivePath or targetPath');
      }

      await _fileService.extract(session, archivePath, targetPath);
      return Result.ok('Extracted');
    } on UnsupportedError catch (e) {
      return Result.fail(400, e.message?.toString() ?? e.toString());
    } catch (e) {
      return Result.fail(500, describeFileOperationError(e));
    }
  }

  Future<Response> deleteFile(Request request) async {
    final path = request.url.queryParameters['path'];
    if (path == null) {
      return Result.fail(400, 'Missing path');
    }

    late final SshSession session;
    try {
      session = await _resolveSession(request);
    } catch (error) {
      return _sessionErrorResponse(error);
    }

    try {
      await _fileService.delete(session, path);
      return Result.ok('Deleted');
    } catch (e) {
      return Result.fail(500, describeFileOperationError(e));
    }
  }
}
