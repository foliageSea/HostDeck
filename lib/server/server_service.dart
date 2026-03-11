import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'ssh_service.dart';

class ServerService {
  HttpServer? _server;
  final int port;
  final SshService _sshService = SshService();

  ServerService({this.port = 8080});

  Future<void> start() async {
    final router = Router();

    // API endpoints
    router.get('/api/status', _statusHandler);
    router.post('/api/connect', _connectHandler);
    router.get('/api/monitor', _monitorHandler);
    router.get('/api/files/list', _listFilesHandler);
    router.get('/api/files/read', _readFileHandler);
    router.post('/api/files/write', _writeFileHandler);
    router.post('/api/files/delete', _deleteFileHandler);
    
    // WebSocket endpoint for terminal
    router.get('/socket.io', (Request request) {
      final sessionId = request.url.queryParameters['sessionId'];
      return webSocketHandler((channel, protocol) {
        if (sessionId != null) {
          final session = _sshService.getSession(sessionId);
          if (session != null) {
            _attachSession(channel, session);
          } else {
            channel.sink.close(4004, 'Session not found');
          }
        } else {
          channel.sink.close(4000, 'Missing sessionId');
        }
      })(request);
    });

    // Fallback handler
    final handler = Pipeline()
        .addMiddleware(logRequests())
        .addHandler(router.call);

    _server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
    print('Server running on port ${_server?.port}');
  }

  Future<void> stop() async {
    await _server?.close();
  }

  Response _statusHandler(Request request) {
    return Response.ok('{"status": "running"}', headers: {'content-type': 'application/json'});
  }

  Future<Response> _connectHandler(Request request) async {
    try {
      final payload = await request.readAsString();
      final data = jsonDecode(payload);
      
      final session = await _sshService.connect(
        host: data['host'],
        port: int.parse(data['port'].toString()),
        username: data['username'],
        password: data['password'],
        privateKey: data['privateKey'],
      );
      
      return Response.ok(jsonEncode({'sessionId': session.id}), 
        headers: {'content-type': 'application/json'});
    } catch (e) {
      print('Connect Error: $e');
      return Response.internalServerError(body: jsonEncode({'error': e.toString()}),
        headers: {'content-type': 'application/json'});
    }
  }

  Future<Response> _monitorHandler(Request request) async {
    // ... (keep existing implementation) ...
    final sessionId = request.url.queryParameters['sessionId'];
    if (sessionId == null) return Response.badRequest(body: 'Missing sessionId');
    
    final session = _sshService.getSession(sessionId);
    if (session == null) return Response.notFound('Session not found');
    
    try {
      // Basic Linux commands for monitoring
      final ramFuture = session.exec('free -m | grep Mem');
      // disk usage of /
      final diskFuture = session.exec("df -h / | awk 'NR==2 {print \$5}'"); 
      // Load average from uptime
      final uptimeFuture = session.exec("uptime");

      final results = await Future.wait([ramFuture, diskFuture, uptimeFuture]);
      
      // Parse RAM
      // Mem: 7963 3855 ...
      final ramParts = results[0].trim().split(RegExp(r'\s+'));
      final totalRam = ramParts.length > 1 ? (int.tryParse(ramParts[1]) ?? 0) : 0;
      final usedRam = ramParts.length > 2 ? (int.tryParse(ramParts[2]) ?? 0) : 0;
      
      final diskUsage = results[1].trim();
      
      // Parse load average from uptime: " 13:22:01 up 1 day,  3:10,  1 user,  load average: 0.00, 0.00, 0.00"
      final uptimeStr = results[2].trim();
      final loadIndex = uptimeStr.indexOf('load average:');
      String loadAvg = '0.0';
      if (loadIndex != -1) {
        final loads = uptimeStr.substring(loadIndex + 13).split(',');
        if (loads.isNotEmpty) {
          loadAvg = loads[0].trim();
        }
      }

      return Response.ok(jsonEncode({
        'cpu': loadAvg, // Using load average for simplicity
        'ram': {'total': totalRam, 'used': usedRam},
        'disk': diskUsage
      }), headers: {'content-type': 'application/json'});
      
    } catch (e) {
      return Response.internalServerError(body: jsonEncode({'error': e.toString()}),
         headers: {'content-type': 'application/json'});
    }
  }

  Future<Response> _listFilesHandler(Request request) async {
    final sessionId = request.url.queryParameters['sessionId'];
    final path = request.url.queryParameters['path'] ?? '.';
    if (sessionId == null) return Response.badRequest(body: 'Missing sessionId');
    
    final session = _sshService.getSession(sessionId);
    if (session == null) return Response.notFound('Session not found');
    
    try {
      final items = await session.listFiles(path);
      // Convert SftpName to simpler map if needed, but we already did in listFiles
      // Wait, listFiles returns List<Map<String, dynamic>>
      return Response.ok(jsonEncode(items), headers: {'content-type': 'application/json'});
    } catch (e) {
      return Response.internalServerError(body: jsonEncode({'error': e.toString()}), headers: {'content-type': 'application/json'});
    }
  }

  Future<Response> _readFileHandler(Request request) async {
    final sessionId = request.url.queryParameters['sessionId'];
    final path = request.url.queryParameters['path'];
    if (sessionId == null || path == null) return Response.badRequest(body: 'Missing sessionId or path');
    
    final session = _sshService.getSession(sessionId);
    if (session == null) return Response.notFound('Session not found');
    
    try {
      final content = await session.readFile(path);
      return Response.ok(content, headers: {'content-type': 'application/octet-stream'});
    } catch (e) {
      return Response.internalServerError(body: e.toString());
    }
  }

  Future<Response> _writeFileHandler(Request request) async {
    final sessionId = request.url.queryParameters['sessionId'];
    final path = request.url.queryParameters['path'];
    if (sessionId == null || path == null) return Response.badRequest(body: 'Missing sessionId or path');
    
    final session = _sshService.getSession(sessionId);
    if (session == null) return Response.notFound('Session not found');
    
    try {
      // Read body as bytes
      final content = await request.read().expand((element) => element).toList();
      await session.writeFile(path, Uint8List.fromList(content));
      return Response.ok('File written');
    } catch (e) {
      return Response.internalServerError(body: e.toString());
    }
  }

  Future<Response> _deleteFileHandler(Request request) async {
    final sessionId = request.url.queryParameters['sessionId'];
    final path = request.url.queryParameters['path'];
    if (sessionId == null || path == null) return Response.badRequest(body: 'Missing sessionId or path');
    
    final session = _sshService.getSession(sessionId);
    if (session == null) return Response.notFound('Session not found');
    
    try {
      await session.delete(path);
      return Response.ok('Deleted');
    } catch (e) {
      return Response.internalServerError(body: e.toString());
    }
  }

  void _attachSession(WebSocketChannel channel, SshSession session) {
    // Forward SSH output to WS
    final sub = session.output.listen((data) {
      channel.sink.add(data);
    }, onDone: () {
      channel.sink.close();
    });

    // Forward WS input to SSH
    channel.stream.listen((message) {
      if (message is String) {
        try {
           if (message.startsWith('{')) {
              final data = jsonDecode(message);
              if (data['type'] == 'resize') {
                session.resize(data['cols'], data['rows']);
                return;
              }
           }
        } catch (_) {}
        
        session.write(message);
      }
    }, onDone: () {
      sub.cancel();
    });
  }
}
