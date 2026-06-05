import 'dart:io';
import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_multipart/shelf_multipart.dart';
import '../models/ssh_session.dart';
import '../services/ssh_service.dart';
import '../services/file_service.dart';
import '../models/result.dart';

class FileController {
  final SshService _sshService;
  final FileService _fileService;
  final Map<String, String> _sharedSessionIds = {};
  final Map<String, Future<SshSession>> _pendingSharedSessions = {};

  FileController(this._sshService, this._fileService);

  Future<SshSession> _getOrCreateSharedSession(String connectionId) async {
    final existingSessionId = _sharedSessionIds[connectionId];
    if (existingSessionId != null) {
      final existingSession = _sshService.getSession(existingSessionId);
      if (existingSession != null) {
        return existingSession;
      }

      _sharedSessionIds.remove(connectionId);
    }

    final pendingSession = _pendingSharedSessions[connectionId];
    if (pendingSession != null) {
      return pendingSession;
    }

    final nextSession = _sshService
        .createSftpSession(connectionId)
        .then((session) {
          _sharedSessionIds[connectionId] = session.id;
          return session;
        })
        .whenComplete(() {
          _pendingSharedSessions.remove(connectionId);
        });

    _pendingSharedSessions[connectionId] = nextSession;
    return nextSession;
  }

  void _removeSharedSessionById(String sessionId) {
    _sharedSessionIds.removeWhere((_, value) => value == sessionId);
  }

  Future<SshSession> _resolveSession(Request request) async {
    final sessionId = request.url.queryParameters['sessionId'];
    if (sessionId != null) {
      final session = _sshService.getSession(sessionId);
      if (session != null) {
        return session;
      }

      throw StateError('Session not found');
    }

    final connectionId = request.url.queryParameters['connectionId'];
    if (connectionId == null) {
      throw ArgumentError('Missing connectionId or sessionId');
    }

    return _getOrCreateSharedSession(connectionId);
  }

  Response _sessionErrorResponse(Object error) {
    if (error is ArgumentError) {
      return Result.fail(400, error.message?.toString() ?? error.toString());
    }

    if (error is StateError) {
      return Result.fail(404, error.message);
    }

    return Result.fail(500, error.toString());
  }

  Future<Response> createSession(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final connectionId = data['connectionId'];

      if (connectionId == null) {
        return Result.fail(400, 'Missing connectionId');
      }

      final session = await _getOrCreateSharedSession(connectionId.toString());

      return Result.ok({'sessionId': session.id});
    } on SshSessionLimitExceeded catch (e) {
      return Result.fail(429, '最多只能创建 ${e.maxSessions} 个 SSH 会话。');
    } catch (e) {
      return Result.fail(500, e.toString());
    }
  }

  Future<Response> closeSession(Request request) async {
    try {
      final sessionId = request.url.queryParameters['sessionId'];
      final connectionId = request.url.queryParameters['connectionId'];

      String? targetSessionId = sessionId;
      if (targetSessionId == null && connectionId != null) {
        targetSessionId = _sharedSessionIds.remove(connectionId);
      }

      if (targetSessionId == null) {
        return Result.fail(400, 'Missing connectionId or sessionId');
      }

      _removeSharedSessionById(targetSessionId);
      await _sshService.closeSession(targetSessionId);

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
      return Result.ok('File written');
    } catch (e) {
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
        }
      } else {
        return Result.fail(400, 'Expected multipart request');
      }

      return Result.ok('Upload complete');
    } catch (e) {
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
      return Result.ok('Renamed');
    } catch (e) {
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
      return Result.ok('Directory created');
    } catch (e) {
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
      return Result.ok('Copied');
    } catch (e) {
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
      return Result.ok('Extracted');
    } on UnsupportedError catch (e) {
      return Result.fail(400, e.message?.toString() ?? e.toString());
    } catch (e) {
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
      return Result.ok('Deleted');
    } catch (e) {
      return Result.fail(500, e.toString());
    }
  }
}
