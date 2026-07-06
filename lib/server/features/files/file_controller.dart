import 'dart:io';
import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_multipart/shelf_multipart.dart';

import 'package:host_deck/server/core/http/result.dart';
import 'package:host_deck/server/core/ssh/shared_ssh_session_resolver.dart';
import 'package:host_deck/server/core/ssh/ssh_service.dart';
import 'package:host_deck/server/core/ssh/ssh_session.dart';
import 'package:host_deck/server/features/files/file_service.dart';
import 'package:host_deck/server/features/operation_logs/operation_log_service.dart';

class FileController {
  final FileService _fileService;
  final OperationLogService _operationLogService;
  final SharedSshSessionResolver _sessionResolver;

  FileController(
    SshService sshService,
    this._fileService,
    this._operationLogService,
  ) : _sessionResolver = SharedSshSessionResolver(
        sshService,
        type: SharedSshSessionType.sftp,
      );

  Future<SshSession> _resolveSession(Request request) async {
    return _sessionResolver.resolveFromRequest(request);
  }

  Response _sessionErrorResponse(Object error) {
    return _sessionResolver.errorResponse(error);
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
      return Result.fail(500, e.toString());
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
      return Result.fail(500, e.toString());
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
      return Response.internalServerError(body: e.toString());
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
      _recordFileSuccess('write', path, session.connectionId);
      return Result.ok('File written');
    } catch (e) {
      _recordFileFailure('write', path, session.connectionId, e);
      return Result.fail(500, e.toString());
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

    try {
      var uploadedCount = 0;
      if (request.multipart() case var multipart?) {
        await for (final part in multipart.parts) {
          final contentDisposition = part.headers['content-disposition'];
          if (contentDisposition == null) continue;

          final headerValue = HeaderValue.parse(contentDisposition);
          final filename = headerValue.parameters['filename'];

          if (filename == null) continue;

          String targetPath = path;
          if (!targetPath.endsWith('/')) targetPath += '/';
          targetPath += filename;

          await _fileService.writeFileStream(session, targetPath, part);
          uploadedCount += 1;
        }
      } else {
        return Result.fail(400, 'Expected multipart request');
      }

      _recordFileSuccess(
        'upload',
        path,
        session.connectionId,
        detail: {'count': uploadedCount},
      );
      return Result.ok('Upload complete');
    } catch (e) {
      _recordFileFailure('upload', path, session.connectionId, e);
      return Result.fail(500, e.toString());
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
      return Response.internalServerError(body: e.toString());
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
      _recordFileSuccess(
        'rename',
        oldPath,
        session.connectionId,
        detail: {'newPath': newPath},
      );
      return Result.ok('Renamed');
    } catch (e) {
      _recordFileFailure('rename', '文件重命名', session.connectionId, e);
      return Result.fail(500, e.toString());
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
      _recordFileSuccess('mkdir', path, session.connectionId);
      return Result.ok('Directory created');
    } catch (e) {
      _recordFileFailure('mkdir', '新建目录', session.connectionId, e);
      return Result.fail(500, e.toString());
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
      _recordFileSuccess(
        'chmod',
        path,
        session.connectionId,
        detail: {'mode': mode, 'recursive': recursive},
      );
      return Result.ok('Permission changed');
    } on ArgumentError catch (e) {
      _recordFileFailure('chmod', '修改权限', session.connectionId, e);
      return Result.fail(400, e.message?.toString() ?? e.toString());
    } catch (e) {
      _recordFileFailure('chmod', '修改权限', session.connectionId, e);
      return Result.fail(500, e.toString());
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
      _recordFileSuccess(
        'copy',
        source,
        session.connectionId,
        detail: {'target': target},
      );
      return Result.ok('Copied');
    } catch (e) {
      _recordFileFailure('copy', '复制文件', session.connectionId, e);
      return Result.fail(500, e.toString());
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
      _recordFileSuccess(
        'extract',
        archivePath,
        session.connectionId,
        detail: {'targetPath': targetPath},
      );
      return Result.ok('Extracted');
    } on UnsupportedError catch (e) {
      _recordFileFailure('extract', '解压文件', session.connectionId, e);
      return Result.fail(400, e.message?.toString() ?? e.toString());
    } catch (e) {
      _recordFileFailure('extract', '解压文件', session.connectionId, e);
      return Result.fail(500, e.toString());
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
      _recordFileSuccess('delete', path, session.connectionId);
      return Result.ok('Deleted');
    } catch (e) {
      _recordFileFailure('delete', path, session.connectionId, e);
      return Result.fail(500, e.toString());
    }
  }

  void _recordFileSuccess(
    String action,
    String? target,
    String connectionId, {
    Map<String, dynamic>? detail,
  }) {
    _operationLogService.success(
      category: 'file',
      action: action,
      target: target,
      detail: detail,
      connectionId: connectionId,
    );
  }

  void _recordFileFailure(
    String action,
    String? target,
    String connectionId,
    Object error,
  ) {
    _operationLogService.failure(
      category: 'file',
      action: action,
      target: target,
      connectionId: connectionId,
      error: error,
    );
  }
}
