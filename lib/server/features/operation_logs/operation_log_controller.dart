import 'package:shelf/shelf.dart';

import 'package:host_deck/server/core/http/result.dart';
import 'package:host_deck/server/features/operation_logs/operation_log_repository.dart';

class OperationLogController {
  final OperationLogRepository _repository;

  OperationLogController(this._repository);

  Future<Response> list(Request request) async {
    try {
      final params = request.url.queryParameters;
      final limit = int.tryParse(params['limit'] ?? '') ?? 100;
      final offset = int.tryParse(params['offset'] ?? '') ?? 0;
      final logs = _repository.list(
        limit: limit,
        offset: offset,
        category: params['category'],
        status: params['status'],
      );
      return Result.ok(logs.map((log) => log.toJson()).toList());
    } catch (e) {
      return Result.fail(500, e.toString());
    }
  }

  Future<Response> clear(Request request) async {
    try {
      _repository.clear();
      return Result.ok({'success': true});
    } catch (e) {
      return Result.fail(500, e.toString());
    }
  }
}
