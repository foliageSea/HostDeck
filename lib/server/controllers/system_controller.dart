import 'package:shelf/shelf.dart';

import '../models/result.dart';
import '../services/monitor_history_service.dart';
import '../services/monitor_service.dart';
import '../services/ssh_service.dart';
import 'system/session_status_ws_handler.dart';
import 'system/system_monitor_ws_handler.dart';

class SystemController {
  final MonitorHistoryService _monitorHistoryService;
  final SshService _sshService;
  final SessionStatusWsHandler _sessionStatusWsHandler;
  final SystemMonitorWsHandler _systemMonitorWsHandler;

  SystemController(
    SshService sshService,
    MonitorService monitorService,
    MonitorHistoryService monitorHistoryService,
  ) : _sshService = sshService,
      _monitorHistoryService = monitorHistoryService,
      _sessionStatusWsHandler = SessionStatusWsHandler(sshService),
      _systemMonitorWsHandler = SystemMonitorWsHandler(
        sshService,
        monitorService,
        monitorHistoryService,
      );

  Response status(Request request) {
    return Result.ok({'status': 'running'});
  }

  Response history(Request request) {
    final connectionId = request.url.queryParameters['connectionId'];
    if (connectionId == null || connectionId.isEmpty) {
      return Result.fail(400, 'Missing connectionId');
    }

    if (_sshService.getClient(connectionId) == null) {
      return Result.fail(404, 'Connection not found');
    }

    final limitParam = request.url.queryParameters['limit'];
    final limit = limitParam == null ? null : int.tryParse(limitParam);
    if (limitParam != null && limit == null) {
      return Result.fail(400, 'Invalid limit');
    }

    final history = _monitorHistoryService.getHistory(
      connectionId,
      limit: limit,
    );

    return Result.ok(history.map((status) => status.toJson()).toList());
  }

  Handler get wsSessionStatus => _sessionStatusWsHandler.handler;

  Handler get wsMonitor => _systemMonitorWsHandler.handler;
}
