import 'package:logging/logging.dart';

import 'package:host_deck/server/features/operation_logs/operation_log_repository.dart';

class OperationLogService {
  final _log = Logger('OperationLogService');
  final OperationLogRepository _repository;

  OperationLogService(this._repository);

  void success({
    required String category,
    required String action,
    String? target,
    Map<String, dynamic>? detail,
    String? connectionId,
  }) {
    _record(
      category: category,
      action: action,
      target: target,
      detail: detail,
      status: 'success',
      connectionId: connectionId,
    );
  }

  void failure({
    required String category,
    required String action,
    String? target,
    Map<String, dynamic>? detail,
    String? connectionId,
    required Object error,
  }) {
    _record(
      category: category,
      action: action,
      target: target,
      detail: detail,
      status: 'failed',
      errorMessage: error.toString(),
      connectionId: connectionId,
    );
  }

  void _record({
    required String category,
    required String action,
    String? target,
    Map<String, dynamic>? detail,
    required String status,
    String? errorMessage,
    String? connectionId,
  }) {
    try {
      _repository.add(
        category: category,
        action: action,
        target: target,
        detail: detail,
        status: status,
        errorMessage: errorMessage,
        connectionId: connectionId,
      );
    } catch (e) {
      _log.warning('Failed to write operation log: $e');
    }
  }
}
