import 'dart:convert';
import 'dart:math';

import 'package:shelf/shelf.dart';

import 'package:host_deck/server/core/http/result.dart';
import 'package:host_deck/server/core/ssh/ssh_service.dart';
import 'package:host_deck/server/features/access/access_auth_service.dart';
import 'package:host_deck/server/features/ai_agent/ai_agent_model.dart';
import 'package:host_deck/server/features/ai_agent/ai_agent_repository.dart';
import 'package:host_deck/server/features/ai_agent/ai_agent_run_manager.dart';
import 'package:host_deck/server/features/ai_agent/ai_agent_settings_service.dart';

class AiAgentController {
  final AiAgentRepository _repository;
  final AiAgentSettingsService _settingsService;
  final AiAgentModelFactory _modelFactory;
  final AiAgentRunManager _runManager;
  final SshService _sshService;

  AiAgentController(
    this._repository,
    this._settingsService,
    this._modelFactory,
    this._runManager,
    this._sshService,
  );

  Response getSettings(Request _) => Result.ok(_settingsService.get().toJson());

  Future<Response> updateSettings(Request request) async {
    try {
      final data = await _readJson(request);
      final settings = _settingsService.update(
        baseUrl: _optionalConfigString(data, 'baseUrl'),
        model: _optionalConfigString(data, 'model'),
        apiKey: _optionalConfigString(data, 'apiKey'),
        clearApiKey: _optionalBool(data, 'clearApiKey') ?? false,
      );
      return Result.ok(settings.toJson());
    } on FormatException catch (error) {
      return Result.fail(400, error.message);
    } catch (_) {
      return Result.fail(500, 'Unable to update AI agent settings.');
    }
  }

  Future<Response> testSettings(Request request) async {
    AiAgentModel? model;
    try {
      final data = await _readJson(request);
      final settings = _settingsService.resolve(
        baseUrl: _optionalConfigString(data, 'baseUrl'),
        model: _optionalConfigString(data, 'model'),
        apiKey: _optionalConfigString(data, 'apiKey'),
      );
      model = _modelFactory.create(settings);
      await model.invoke(const [
        AiAgentModelMessage(role: 'user', content: 'Reply with OK.'),
      ], const []);
      return Result.ok({'success': true});
    } on FormatException catch (error) {
      return Result.fail(400, error.message);
    } on StateError catch (error) {
      return Result.fail(400, error.message);
    } catch (_) {
      return Result.fail(502, 'Unable to connect to the configured model.');
    } finally {
      model?.close();
    }
  }

  Response listConversations(Request request) {
    try {
      final targetKey = _targetKey(request.url.queryParameters['connectionId']);
      final limit = int.tryParse(request.url.queryParameters['limit'] ?? '');
      final offset = int.tryParse(request.url.queryParameters['offset'] ?? '');
      return Result.ok(
        _repository
            .listConversations(
              targetKey,
              limit: limit ?? 50,
              offset: offset ?? 0,
            )
            .map((item) => item.toJson())
            .toList(),
      );
    } on ArgumentError catch (error) {
      return Result.fail(400, error.message?.toString() ?? 'Invalid request.');
    } on FormatException catch (error) {
      return Result.fail(400, error.message);
    } on StateError catch (error) {
      return Result.fail(404, error.message);
    }
  }

  Future<Response> createConversation(Request request) async {
    try {
      final data = await _readJson(request);
      final connectionId = _requiredString(data, 'connectionId');
      final conversation = _repository.createConversation(
        _newId(),
        _targetKey(connectionId),
      );
      return Result.ok(conversation.toJson());
    } on ArgumentError catch (error) {
      return Result.fail(400, error.message?.toString() ?? 'Invalid request.');
    } on FormatException catch (error) {
      return Result.fail(400, error.message);
    } on StateError catch (error) {
      return Result.fail(404, error.message);
    } catch (_) {
      return Result.fail(500, 'Unable to create conversation.');
    }
  }

  Response getConversation(Request request, String id) {
    try {
      final targetKey = _targetKey(request.url.queryParameters['connectionId']);
      final conversation = _repository.getConversation(id, targetKey);
      if (conversation == null) {
        return Result.fail(404, 'Conversation not found.');
      }
      return Result.ok({
        'conversation': conversation.toJson(),
        'messages': _repository
            .listMessages(id)
            .map((message) => message.toJson())
            .toList(),
      });
    } on ArgumentError catch (error) {
      return Result.fail(400, error.message?.toString() ?? 'Invalid request.');
    } on FormatException catch (error) {
      return Result.fail(400, error.message);
    } on StateError catch (error) {
      return Result.fail(404, error.message);
    }
  }

  Future<Response> updateConversation(Request request, String id) async {
    try {
      final data = await _readJson(request);
      final targetKey = _targetKey(_requiredString(data, 'connectionId'));
      final title = _requiredString(data, 'title').trim();
      if (title.length > 100) {
        return Result.fail(400, 'Title must not exceed 100 characters.');
      }
      final conversation = _repository.updateConversationTitle(
        id,
        targetKey,
        title,
      );
      if (conversation == null) {
        return Result.fail(404, 'Conversation not found.');
      }
      return Result.ok(conversation.toJson());
    } on ArgumentError catch (error) {
      return Result.fail(400, error.message?.toString() ?? 'Invalid request.');
    } on FormatException catch (error) {
      return Result.fail(400, error.message);
    } on StateError catch (error) {
      return Result.fail(404, error.message);
    } catch (_) {
      return Result.fail(500, 'Unable to update conversation.');
    }
  }

  Response deleteConversation(Request request, String id) {
    try {
      final targetKey = _targetKey(request.url.queryParameters['connectionId']);
      if (_repository.getConversation(id, targetKey) == null) {
        return Result.fail(404, 'Conversation not found.');
      }
      _runManager.cancelConversation(id);
      _repository.deleteConversation(id, targetKey);
      return Result.ok({'success': true});
    } on ArgumentError catch (error) {
      return Result.fail(400, error.message?.toString() ?? 'Invalid request.');
    } on FormatException catch (error) {
      return Result.fail(400, error.message);
    } on StateError catch (error) {
      return Result.fail(404, error.message);
    }
  }

  Future<Response> run(Request request, String id) async {
    try {
      final data = await _readJson(request);
      final connectionId = _requiredString(data, 'connectionId');
      final input = _requiredString(data, 'input');
      if (utf8.encode(input).length > 32 * 1024) {
        return Result.fail(400, 'Input is too large.');
      }
      final targetKey = _targetKey(connectionId);
      if (_repository.getConversation(id, targetKey) == null) {
        return Result.fail(404, 'Conversation not found.');
      }
      final run = _runManager.start(
        conversationId: id,
        connectionId: connectionId,
        targetKey: targetKey,
        ownerId: _principalId(request),
        input: input,
      );
      return Response.ok(
        run.stream,
        headers: const {
          'content-type': 'text/event-stream; charset=utf-8',
          'cache-control': 'no-cache, no-transform',
          'connection': 'keep-alive',
          'x-accel-buffering': 'no',
        },
        context: const {'shelf.io.buffer_output': false},
      );
    } on ArgumentError catch (error) {
      return Result.fail(400, error.message?.toString() ?? 'Invalid request.');
    } on FormatException catch (error) {
      return Result.fail(400, error.message);
    } on StateError catch (error) {
      final message = error.message;
      final code =
          message == 'A run is already active for this conversation.' ||
              message == 'Too many AI agent runs are active.'
          ? 409
          : 404;
      return Result.fail(code, message);
    } catch (_) {
      return Result.fail(500, 'Unable to start AI agent run.');
    }
  }

  Future<Response> approve(Request request, String runId) =>
      _approval(request, runId, approved: true);

  Future<Response> reject(Request request, String runId) =>
      _approval(request, runId, approved: false);

  Response cancel(Request request, String runId) {
    if (!_runManager.cancel(runId, ownerId: _principalId(request))) {
      return Result.fail(404, 'Run not found.');
    }
    return Result.ok({'success': true});
  }

  Future<Response> _approval(
    Request request,
    String runId, {
    required bool approved,
  }) async {
    try {
      final data = await _readJson(request);
      final callId = _requiredString(data, 'callId');
      final result = approved
          ? _runManager.approve(runId, callId, _principalId(request))
          : _runManager.reject(runId, callId, _principalId(request));
      return switch (result) {
        AiAgentApprovalResult.accepted => Result.ok({'success': true}),
        AiAgentApprovalResult.mismatch => Result.fail(
          409,
          'Approval does not match the pending tool call.',
        ),
        AiAgentApprovalResult.expired => Result.fail(410, 'Approval expired.'),
        AiAgentApprovalResult.notFound => Result.fail(
          404,
          'Pending approval not found.',
        ),
      };
    } on ArgumentError catch (error) {
      return Result.fail(400, error.message?.toString() ?? 'Invalid request.');
    } on FormatException catch (error) {
      return Result.fail(400, error.message);
    }
  }

  String _targetKey(String? connectionId) {
    if (connectionId == null || connectionId.isEmpty) {
      throw ArgumentError('Missing connectionId.');
    }
    final metadata = _sshService.getConnectionMetadata(connectionId);
    if (metadata == null) throw StateError('Connection not found.');
    return metadata.targetKey;
  }

  Future<Map<String, dynamic>> _readJson(Request request) async {
    final body = await request.readAsString();
    if (body.trim().isEmpty) return {};
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('JSON object required.');
    }
    return decoded;
  }

  String _requiredString(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value is! String || value.trim().isEmpty) {
      throw ArgumentError('Missing $key.');
    }
    return value;
  }

  String? _optionalConfigString(Map<String, dynamic> data, String key) {
    if (!data.containsKey(key)) return null;
    final value = data[key];
    if (value is! String) throw FormatException('$key must be a string.');
    return value;
  }

  bool? _optionalBool(Map<String, dynamic> data, String key) {
    if (!data.containsKey(key)) return null;
    final value = data[key];
    if (value is! bool) throw FormatException('$key must be a boolean.');
    return value;
  }

  String _newId() {
    final random = Random.secure();
    final bytes = List<int>.generate(24, (_) => random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  String _principalId(Request request) {
    final principal =
        request.context[AccessAuthService.principalContextKey]
            as AccessPrincipal?;
    return principal == null
        ? 'anonymous'
        : '${principal.type}:${principal.id}';
  }
}
