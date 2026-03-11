import 'dart:convert';
import 'dart:typed_data';
import 'package:shelf/shelf.dart';
import '../services/ssh_service.dart';
import '../services/file_service.dart';

class FileController {
  final SshService _sshService;
  final FileService _fileService;

  FileController(this._sshService, this._fileService);

  Future<Response> listFiles(Request request) async {
    final sessionId = request.url.queryParameters['sessionId'];
    final path = request.url.queryParameters['path'] ?? '.';
    if (sessionId == null) return Response.badRequest(body: 'Missing sessionId');
    
    final session = _sshService.getSession(sessionId);
    if (session == null) return Response.notFound('Session not found');
    
    try {
      final items = await _fileService.listFiles(session, path);
      return Response.ok(jsonEncode(items), headers: {'content-type': 'application/json'});
    } catch (e) {
      return Response.internalServerError(body: jsonEncode({'error': e.toString()}), headers: {'content-type': 'application/json'});
    }
  }

  Future<Response> readFile(Request request) async {
    final sessionId = request.url.queryParameters['sessionId'];
    final path = request.url.queryParameters['path'];
    if (sessionId == null || path == null) return Response.badRequest(body: 'Missing sessionId or path');
    
    final session = _sshService.getSession(sessionId);
    if (session == null) return Response.notFound('Session not found');
    
    try {
      final content = await _fileService.readFile(session, path);
      return Response.ok(content, headers: {'content-type': 'application/octet-stream'});
    } catch (e) {
      return Response.internalServerError(body: e.toString());
    }
  }

  Future<Response> writeFile(Request request) async {
    final sessionId = request.url.queryParameters['sessionId'];
    final path = request.url.queryParameters['path'];
    if (sessionId == null || path == null) return Response.badRequest(body: 'Missing sessionId or path');
    
    final session = _sshService.getSession(sessionId);
    if (session == null) return Response.notFound('Session not found');
    
    try {
      final content = await request.read().expand((element) => element).toList();
      await _fileService.writeFile(session, path, Uint8List.fromList(content));
      return Response.ok('File written');
    } catch (e) {
      return Response.internalServerError(body: e.toString());
    }
  }

  Future<Response> deleteFile(Request request) async {
    final sessionId = request.url.queryParameters['sessionId'];
    final path = request.url.queryParameters['path'];
    if (sessionId == null || path == null) return Response.badRequest(body: 'Missing sessionId or path');
    
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
