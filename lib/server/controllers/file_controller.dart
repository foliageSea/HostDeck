import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:shelf/shelf.dart';
import 'package:shelf_multipart/shelf_multipart.dart';
import '../services/ssh_service.dart';
import '../services/file_service.dart';

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
        return Response.badRequest(body: 'Missing connectionId');
      }

      final session = await _sshService.createSftpSession(connectionId);
      
      return Response.ok(jsonEncode({
        'sessionId': session.id,
      }), headers: {'content-type': 'application/json'});
    } catch (e) {
      return Response.internalServerError(body: jsonEncode({'error': e.toString()}),
        headers: {'content-type': 'application/json'});
    }
  }

  Future<Response> listFiles(Request request) async {
    final sessionId = request.url.queryParameters['sessionId'];
    final path = request.url.queryParameters['path'] ?? '.';
    if (sessionId == null)
      return Response.badRequest(body: 'Missing sessionId');

    final session = _sshService.getSession(sessionId);
    if (session == null) return Response.notFound('Session not found');

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
      return Response.ok(
        jsonEncode(jsonItems),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  Future<Response> readFile(Request request) async {
    final sessionId = request.url.queryParameters['sessionId'];
    final path = request.url.queryParameters['path'];
    if (sessionId == null || path == null)
      return Response.badRequest(body: 'Missing sessionId or path');

    final session = _sshService.getSession(sessionId);
    if (session == null) return Response.notFound('Session not found');

    try {
      final stream = await _fileService.readFileStream(session, path);
      return Response.ok(
        stream,
        headers: {'content-type': 'application/octet-stream'},
      );
    } catch (e) {
      return Response.internalServerError(body: e.toString());
    }
  }

  Future<Response> writeFile(Request request) async {
    final sessionId = request.url.queryParameters['sessionId'];
    final path = request.url.queryParameters['path'];
    if (sessionId == null || path == null)
      return Response.badRequest(body: 'Missing sessionId or path');

    final session = _sshService.getSession(sessionId);
    if (session == null) return Response.notFound('Session not found');

    try {
      await _fileService.writeFileStream(session, path, request.read());
      return Response.ok('File written');
    } catch (e) {
      return Response.internalServerError(body: e.toString());
    }
  }

  Future<Response> uploadFile(Request request) async {
    final sessionId = request.url.queryParameters['sessionId'];
    final path = request.url.queryParameters['path'];
    if (sessionId == null || path == null)
      return Response.badRequest(body: 'Missing sessionId or path');

    final session = _sshService.getSession(sessionId);
    if (session == null) return Response.notFound('Session not found');

    // if (!request.isMultipart) {
    //   return Response.badRequest(body: 'Expected multipart request');
    // }

    try {
      // await for (final part in request.parts) {
      //   final contentDisposition = part.headers['content-disposition'];
      //   if (contentDisposition == null) continue;

      //   final headerValue = HeaderValue.parse(contentDisposition);
      //   final filename = headerValue.parameters['filename'];

      //   if (filename == null) continue;

      //   String targetPath = path;
      //   if (!targetPath.endsWith('/')) targetPath += '/';
      //   targetPath += filename;

      //   await _fileService.writeFileStream(session, targetPath, part.read());
      // }

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
        return Response.badRequest(body: 'Expected multipart request');
      }

      return Response.ok('Upload complete');
    } catch (e) {
      return Response.internalServerError(body: e.toString());
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
    if (sessionId == null)
      return Response.badRequest(body: 'Missing sessionId');

    final session = _sshService.getSession(sessionId);
    if (session == null) return Response.notFound('Session not found');

    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final oldPath = data['oldPath'] as String;
      final newPath = data['newPath'] as String;

      await _fileService.rename(session, oldPath, newPath);
      return Response.ok('Renamed');
    } catch (e) {
      return Response.internalServerError(body: e.toString());
    }
  }

  Future<Response> mkdir(Request request) async {
    final sessionId = request.url.queryParameters['sessionId'];
    if (sessionId == null)
      return Response.badRequest(body: 'Missing sessionId');

    final session = _sshService.getSession(sessionId);
    if (session == null) return Response.notFound('Session not found');

    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final path = data['path'] as String;

      await _fileService.mkdir(session, path);
      return Response.ok('Directory created');
    } catch (e) {
      return Response.internalServerError(body: e.toString());
    }
  }

  Future<Response> copy(Request request) async {
    final sessionId = request.url.queryParameters['sessionId'];
    if (sessionId == null)
      return Response.badRequest(body: 'Missing sessionId');

    final session = _sshService.getSession(sessionId);
    if (session == null) return Response.notFound('Session not found');

    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final source = data['source'] as String;
      final target = data['target'] as String;

      await _fileService.copy(session, source, target);
      return Response.ok('Copied');
    } catch (e) {
      return Response.internalServerError(body: e.toString());
    }
  }

  Future<Response> deleteFile(Request request) async {
    final sessionId = request.url.queryParameters['sessionId'];
    final path = request.url.queryParameters['path'];
    if (sessionId == null || path == null)
      return Response.badRequest(body: 'Missing sessionId or path');

    final session = _sshService.getSession(sessionId);
    if (session == null) return Response.notFound('Session not found');

    try {
      await _fileService.delete(session, path);
      return Response.ok('Deleted');
    } catch (e) {
      return Response.internalServerError(body: e.toString());
    }
  }
}
