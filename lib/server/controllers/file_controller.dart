import 'dart:io';
import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_multipart/shelf_multipart.dart';
import '../services/ssh_service.dart';
import '../services/file_service.dart';
import '../models/result.dart';

class FileController {
  final SshService _sshService;
  final FileService _fileService;

  FileController(this._sshService, this._fileService);

  Future<Response> createSession(Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final connectionId = data['connectionId'];

      if (connectionId == null) {
        return Result.fail(400, 'Missing connectionId');
      }

      final session = await _sshService.createSftpSession(connectionId);

      return Result.ok({'sessionId': session.id});
    } catch (e) {
      return Result.fail(500, e.toString());
    }
  }

  Future<Response> closeSession(Request request) async {
    try {
      final sessionId = request.url.queryParameters['sessionId'];
      if (sessionId == null) {
        return Result.fail(400, 'Missing sessionId');
      }

      await _sshService.closeSession(sessionId);

      return Result.ok('Session closed');
    } catch (e) {
      return Result.fail(500, e.toString());
    }
  }

  Future<Response> listFiles(Request request) async {
    final sessionId = request.url.queryParameters['sessionId'];
    final path = request.url.queryParameters['path'] ?? '.';
    if (sessionId == null) return Result.fail(400, 'Missing sessionId');

    final session = _sshService.getSession(sessionId);
    if (session == null) return Result.fail(404, 'Session not found');

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

  Future<Response> readFile(Request request) async {
    final sessionId = request.url.queryParameters['sessionId'];
    final path = request.url.queryParameters['path'];
    final download = request.url.queryParameters['download'] == 'true';

    if (sessionId == null || path == null)
      return Response.badRequest(body: 'Missing sessionId or path');

    final session = _sshService.getSession(sessionId);
    if (session == null) return Response.notFound('Session not found');

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
    final sessionId = request.url.queryParameters['sessionId'];
    final path = request.url.queryParameters['path'];
    if (sessionId == null || path == null)
      return Result.fail(400, 'Missing sessionId or path');

    final session = _sshService.getSession(sessionId);
    if (session == null) return Result.fail(404, 'Session not found');

    try {
      await _fileService.writeFileStream(session, path, request.read());
      return Result.ok('File written');
    } catch (e) {
      return Result.fail(500, e.toString());
    }
  }

  Future<Response> uploadFile(Request request) async {
    final sessionId = request.url.queryParameters['sessionId'];
    final path = request.url.queryParameters['path'];
    if (sessionId == null || path == null)
      return Result.fail(400, 'Missing sessionId or path');

    final session = _sshService.getSession(sessionId);
    if (session == null) return Result.fail(404, 'Session not found');

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
    final sessionId = request.url.queryParameters['sessionId'];
    if (sessionId == null)
      return Response.badRequest(body: 'Missing sessionId');

    final session = _sshService.getSession(sessionId);
    if (session == null) return Response.notFound('Session not found');

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
    final sessionId = request.url.queryParameters['sessionId'];
    if (sessionId == null) return Result.fail(400, 'Missing sessionId');

    final session = _sshService.getSession(sessionId);
    if (session == null) return Result.fail(404, 'Session not found');

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
    final sessionId = request.url.queryParameters['sessionId'];
    if (sessionId == null) return Result.fail(400, 'Missing sessionId');

    final session = _sshService.getSession(sessionId);
    if (session == null) return Result.fail(404, 'Session not found');

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
    final sessionId = request.url.queryParameters['sessionId'];
    if (sessionId == null) return Result.fail(400, 'Missing sessionId');

    final session = _sshService.getSession(sessionId);
    if (session == null) return Result.fail(404, 'Session not found');

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

  Future<Response> deleteFile(Request request) async {
    final sessionId = request.url.queryParameters['sessionId'];
    final path = request.url.queryParameters['path'];
    if (sessionId == null || path == null)
      return Result.fail(400, 'Missing sessionId or path');

    final session = _sshService.getSession(sessionId);
    if (session == null) return Result.fail(404, 'Session not found');

    try {
      await _fileService.delete(session, path);
      return Result.ok('Deleted');
    } catch (e) {
      return Result.fail(500, e.toString());
    }
  }
}
