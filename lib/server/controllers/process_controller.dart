import 'dart:convert';

import 'package:shelf/shelf.dart';

import 'process/process_session_manager.dart';
import 'process/process_ws_handler.dart';
import '../models/ssh_session.dart';
import '../models/result.dart';
import '../services/process_service.dart';
import '../services/ssh_service.dart';

class ProcessController {
  final ProcessService _processService;
  final ProcessSessionManager _sessionManager;
  late final ProcessWsHandler _processWsHandler;

  ProcessController(SshService sshService, this._processService)
    : _sessionManager = ProcessSessionManager(sshService) {
    _processWsHandler = ProcessWsHandler(
      sshService,
      _processService,
      _sessionManager,
    );
  }

  Handler get wsProcesses => _processWsHandler.handler;

  Response _sessionErrorResponse(Object error) {
    if (error is ArgumentError) {
      return Result.fail(400, error.message?.toString() ?? error.toString());
    }

    if (error is StateError) {
      return Result.fail(404, error.message);
    }

    return Result.fail(500, error.toString());
  }

  Future<Response> listProcesses(Request request) async {
    try {
      final session = await _resolveSession(
        request.url.queryParameters['connectionId'],
      );
      final limitParam = request.url.queryParameters['limit'];
      final limit = limitParam == null ? null : int.tryParse(limitParam);
      if (limitParam != null && limit == null) {
        return Result.fail(400, 'Invalid limit');
      }

      final processes = await _processService.listProcesses(
        session,
        keyword: request.url.queryParameters['keyword'],
        user: request.url.queryParameters['user'],
        sortBy: request.url.queryParameters['sortBy'] ?? 'cpu',
        sortOrder: request.url.queryParameters['sortOrder'] ?? 'desc',
        limit: limit,
      );
      return Result.ok(processes.map((item) => item.toJson()).toList());
    } on ArgumentError catch (error) {
      return _sessionErrorResponse(error);
    } on StateError catch (error) {
      return _sessionErrorResponse(error);
    } catch (e) {
      return Result.fail(500, e.toString());
    }
  }

  Future<Response> getProcessDetail(Request request, String pidParam) async {
    try {
      final pid = int.tryParse(pidParam);
      if (pid == null || pid <= 0) {
        return Result.fail(400, 'Invalid pid');
      }

      final session = await _resolveSession(
        request.url.queryParameters['connectionId'],
      );
      final detail = await _processService.getProcessDetail(session, pid);
      return Result.ok(detail.toJson());
    } on ArgumentError catch (error) {
      return _sessionErrorResponse(error);
    } on StateError catch (error) {
      return _sessionErrorResponse(error);
    } catch (e) {
      return Result.fail(500, e.toString());
    }
  }

  Future<Response> getProcessTree(Request request) async {
    try {
      final session = await _resolveSession(
        request.url.queryParameters['connectionId'],
      );
      final tree = await _processService.getProcessTree(
        session,
        keyword: request.url.queryParameters['keyword'],
        user: request.url.queryParameters['user'],
      );
      return Result.ok(tree.map((item) => item.toJson()).toList());
    } on ArgumentError catch (error) {
      return _sessionErrorResponse(error);
    } on StateError catch (error) {
      return _sessionErrorResponse(error);
    } catch (e) {
      return Result.fail(500, e.toString());
    }
  }

  Future<Response> sendSignal(Request request, String pidParam) async {
    try {
      final pid = int.tryParse(pidParam);
      if (pid == null || pid <= 0) {
        return Result.fail(400, 'Invalid pid');
      }

      final payload = await request.readAsString();
      final data = jsonDecode(payload) as Map<String, dynamic>;
      final connectionId = data['connectionId'] as String?;
      final signal = (data['signal'] as String?)?.trim();
      if (signal == null || signal.isEmpty) {
        return Result.fail(400, 'Missing signal');
      }

      final session = await _resolveSession(connectionId);
      await _processService.sendSignal(session, pid, signal);
      return Result.ok({'success': true});
    } on ArgumentError catch (error) {
      return _sessionErrorResponse(error);
    } on StateError catch (error) {
      return _sessionErrorResponse(error);
    } catch (e) {
      return Result.fail(500, e.toString());
    }
  }

  Future<Response> startProcess(Request request) async {
    try {
      final payload = await request.readAsString();
      final data = jsonDecode(payload) as Map<String, dynamic>;
      final connectionId = data['connectionId'] as String?;
      final command = (data['command'] as String?)?.trim();
      if (command == null || command.isEmpty) {
        return Result.fail(400, 'Missing command');
      }

      final session = await _resolveSession(connectionId);
      final environment = <String, String>{};
      final rawEnvironment = data['environment'];
      if (rawEnvironment is Map) {
        for (final entry in rawEnvironment.entries) {
          if (entry.key is String && entry.value is String) {
            environment[entry.key as String] = entry.value as String;
          }
        }
      }

      final result = await _processService.startProcess(
        session,
        command: command,
        workingDirectory: data['workingDirectory'] as String?,
        environment: environment,
      );
      return Result.ok(result.toJson());
    } on ArgumentError catch (error) {
      return _sessionErrorResponse(error);
    } on StateError catch (error) {
      return _sessionErrorResponse(error);
    } catch (e) {
      return Result.fail(500, e.toString());
    }
  }

  Future<SshSession> _resolveSession(String? connectionId) async {
    return _sessionManager.resolveSession(connectionId);
  }
}
