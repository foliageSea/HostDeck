import 'dart:async';
import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../models/ssh_session.dart';
import '../../services/process_service.dart';
import '../../services/ssh_service.dart';
import 'process_session_manager.dart';

class ProcessWsHandler {
  final SshService _sshService;
  final ProcessService _processService;
  final ProcessSessionManager _sessionManager;

  ProcessWsHandler(this._sshService, this._processService, this._sessionManager);

  Handler get handler {
    return (Request request) {
      return webSocketHandler((WebSocketChannel channel, String? protocol) {
        Timer? timer;
        var isActive = true;

        var connectionId = request.url.queryParameters['connectionId'];
        var keyword = request.url.queryParameters['keyword'];
        var user = request.url.queryParameters['user'];
        var sortBy = request.url.queryParameters['sortBy'] ?? 'cpu';
        var sortOrder = request.url.queryParameters['sortOrder'] ?? 'desc';
        var includeTree = request.url.queryParameters['includeTree'] == 'true';
        var selectedPid = _parseSelectedPid(
          request.url.queryParameters['selectedPid'],
        );

        Future<Map<String, dynamic>> buildSnapshot(SshSession session) async {
          final processes = await _processService.listProcesses(
            session,
            keyword: keyword,
            user: user,
            sortBy: sortBy,
            sortOrder: sortOrder,
            limit: 300,
          );

          final data = <String, dynamic>{
            'processes': processes.map((item) => item.toJson()).toList(),
            'refreshedAt': DateTime.now().millisecondsSinceEpoch,
          };

          if (includeTree) {
            data['tree'] = _processService
                .buildProcessTree(processes)
                .map((item) => item.toJson())
                .toList();
          }

          if (selectedPid != null) {
            final processExists = processes.any((item) => item.pid == selectedPid);
            final detail = processExists
                ? await _processService.getProcessDetailOrNull(
                    session,
                    selectedPid!,
                  )
                : null;
            data['detail'] = detail?.toJson();
          } else {
            data['detail'] = null;
          }

          return data;
        }

        Future<void> sendSnapshot() async {
          if (!isActive) {
            return;
          }

          try {
            final session = await _sessionManager.resolveSession(connectionId);
            final snapshot = await buildSnapshot(session);
            if (!isActive) {
              return;
            }

            channel.sink.add(
              jsonEncode({
                'code': 200,
                'data': snapshot,
                'message': 'success',
              }),
            );
          } on ArgumentError catch (error) {
            channel.sink.add(
              jsonEncode({
                'code': 400,
                'data': null,
                'message': error.message?.toString() ?? error.toString(),
              }),
            );
          } on StateError catch (error) {
            channel.sink.add(
              jsonEncode({'code': 404, 'data': null, 'message': error.message}),
            );
          } catch (error) {
            channel.sink.add(
              jsonEncode({
                'code': 500,
                'data': null,
                'message': error.toString(),
              }),
            );
          }
        }

        void dispose() {
          isActive = false;
          timer?.cancel();
          timer = null;
        }

        if (connectionId == null || connectionId.isEmpty) {
          channel.sink.close(4000, 'Missing connectionId parameter');
          return;
        }

        if (_sshService.getClient(connectionId) == null) {
          channel.sink.close(4004, 'Connection not found');
          return;
        }

        unawaited(sendSnapshot());
        timer = Timer.periodic(const Duration(seconds: 5), (_) {
          unawaited(sendSnapshot());
        });

        channel.stream.listen(
          (message) {
            if (message == 'ping') {
              channel.sink.add('pong');
              return;
            }

            if (message == 'refresh') {
              unawaited(sendSnapshot());
              return;
            }

            if (message is! String || message.isEmpty || !message.startsWith('{')) {
              return;
            }

            try {
              final data = jsonDecode(message) as Map<String, dynamic>;
              if (data['type'] != 'updateFilters') {
                return;
              }

              final payload = data['payload'];
              if (payload is! Map<String, dynamic>) {
                return;
              }

              final nextKeyword = payload['keyword'];
              final nextUser = payload['user'];
              final nextSortBy = payload['sortBy'];
              final nextSortOrder = payload['sortOrder'];
              final nextIncludeTree = payload['includeTree'];
              final nextSelectedPid = payload['selectedPid'];

              keyword = nextKeyword is String && nextKeyword.trim().isNotEmpty
                  ? nextKeyword.trim()
                  : null;
              user = nextUser is String && nextUser.trim().isNotEmpty
                  ? nextUser.trim()
                  : null;
              sortBy = nextSortBy is String && nextSortBy.trim().isNotEmpty
                  ? nextSortBy.trim()
                  : 'cpu';
              sortOrder =
                  nextSortOrder is String && nextSortOrder.trim().isNotEmpty
                  ? nextSortOrder.trim()
                  : 'desc';
              includeTree = nextIncludeTree == true;
              selectedPid = _parseSelectedPid(nextSelectedPid);

              unawaited(sendSnapshot());
            } catch (_) {}
          },
          onDone: dispose,
          onError: (_) {
            dispose();
          },
        );
      })(request);
    };
  }

  int? _parseSelectedPid(Object? value) {
    if (value is int) {
      return value > 0 ? value : null;
    }

    if (value is String) {
      final normalized = value.trim();
      if (normalized.isEmpty) {
        return null;
      }

      final pid = int.tryParse(normalized);
      return pid != null && pid > 0 ? pid : null;
    }

    return null;
  }
}
