import 'package:shelf/shelf.dart';

import '../models/result.dart';
import '../services/monitor_service.dart';
import '../services/ssh_service.dart';
import 'system/session_status_ws_handler.dart';
import 'system/system_monitor_ws_handler.dart';

class SystemController {
  final SessionStatusWsHandler _sessionStatusWsHandler;
  final SystemMonitorWsHandler _systemMonitorWsHandler;

  SystemController(SshService sshService, MonitorService monitorService)
    : _sessionStatusWsHandler = SessionStatusWsHandler(sshService),
      _systemMonitorWsHandler = SystemMonitorWsHandler(
        sshService,
        monitorService,
      );

  Response status(Request request) {
    return Result.ok({'status': 'running'});
  }

  Handler get wsSessionStatus => _sessionStatusWsHandler.handler;

  Handler get wsMonitor => _systemMonitorWsHandler.handler;
}
