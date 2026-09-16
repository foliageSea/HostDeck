import 'dart:convert';
import 'dart:math';

import 'package:shelf/shelf.dart';

import 'package:host_deck/server/core/http/result.dart';
import 'package:host_deck/server/core/ssh/shared_ssh_session_resolver.dart';
import 'package:host_deck/server/core/ssh/ssh_service.dart';
import 'package:host_deck/server/features/access/access_auth_service.dart';
import 'package:host_deck/server/features/ai_agent/ai_agent_model.dart';
import 'package:host_deck/server/features/ai_agent/ai_agent_mcp_service.dart';
import 'package:host_deck/server/features/ai_agent/ai_agent_repository.dart';
import 'package:host_deck/server/features/ai_agent/ai_agent_run_manager.dart';
import 'package:host_deck/server/features/ai_agent/ai_agent_settings_service.dart';
import 'package:host_deck/server/features/ai_agent/ai_agent_skill_service.dart';

class AiAgentController {
  final AiAgentRepository _repository;
  final AiAgentSettingsService _settingsService;
  final AiAgentModelFactory _modelFactory;
  final AiAgentRunManager _runManager;
  final SshService _sshService;
  final AiAgentSkillService _skillService;
  final AiAgentMcpRepository _mcpRepository;
  final AiAgentMcpClient _mcpClient;
  final SharedSshSessionResolver _sessionResolver;

  AiAgentController(
    this._repository,
    this._settingsService,
    this._modelFactory,
    this._runManager,
    this._sshService,
    this._skillService,
    this._mcpRepository,
    this._mcpClient,
    this._sessionResolver,
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

  Future<Response> listSkills(Request request) async {
    try {
      final connectionId = request.url.queryParameters['connectionId'];
      _targetKey(connectionId);
      final skills = await _skillService.discover(connectionId!);
      return Result.ok(skills.map((skill) => skill.toJson()).toList());
    } on ArgumentError catch (error) {
      return Result.fail(400, error.message?.toString() ?? 'Invalid request.');
    } on StateError catch (error) {
      return Result.fail(404, error.message);
    } catch (_) {
      return Result.fail(500, 'Unable to discover AI agent skills.');
    }
  }

  Future<Response> closeSession(Request request) async {
    try {
      await _sessionResolver.closeFromRequest(request);
      return Result.ok({'success': true});
    } catch (error) {
      return _sessionResolver.errorResponse(error);
    }
  }

  Response listMcpServers(Request _) => Result.ok(
    _mcpRepository.list().map((server) => server.toJson()).toList(),
  );

  Future<Response> createMcpServer(Request request) async {
    try {
      final data = await _readJson(request);
      final server = _mcpRepository.create(
        name: _mcpName(data),
        url: _mcpUrl(data),
        headers: _mcpHeaders(data) ?? const {},
        enabled: _optionalBool(data, 'enabled') ?? true,
      );
      return Result.ok(server.toJson());
    } on ArgumentError catch (error) {
      return Result.fail(
        400,
        error.message?.toString() ?? 'Invalid MCP server.',
      );
    } on FormatException catch (error) {
      return Result.fail(400, error.message);
    } catch (_) {
      return Result.fail(500, 'Unable to create MCP server.');
    }
  }

  Future<Response> updateMcpServer(Request request, String id) async {
    try {
      final serverId = int.tryParse(id);
      if (serverId == null) return Result.fail(400, 'Invalid MCP server id.');
      final data = await _readJson(request);
      final server = _mcpRepository.update(
        serverId,
        name: _mcpName(data),
        url: _mcpUrl(data),
        headers: _mcpHeaders(data),
        enabled: _optionalBool(data, 'enabled') ?? true,
        clearHeaders: _optionalBool(data, 'clearHeaders') ?? false,
      );
      return server == null
          ? Result.fail(404, 'MCP server not found.')
          : Result.ok(server.toJson());
    } on ArgumentError catch (error) {
      return Result.fail(
        400,
        error.message?.toString() ?? 'Invalid MCP server.',
      );
    } on FormatException catch (error) {
      return Result.fail(400, error.message);
    } catch (_) {
      return Result.fail(500, 'Unable to update MCP server.');
    }
  }

  Response deleteMcpServer(Request _, String id) {
    final serverId = int.tryParse(id);
    if (serverId == null) return Result.fail(400, 'Invalid MCP server id.');
    return _mcpRepository.delete(serverId)
        ? Result.ok({'success': true})
        : Result.fail(404, 'MCP server not found.');
  }

  Future<Response> testMcpServer(Request request, String id) async {
    try {
      final serverId = int.tryParse(id);
      if (serverId == null) return Result.fail(400, 'Invalid MCP server id.');
      final server = _mcpRepository.get(serverId);
      if (server == null) return Result.fail(404, 'MCP server not found.');
      final tools = await _mcpClient.listTools(server);
      return Result.ok({'success': true, 'toolCount': tools.length});
    } catch (_) {
      return Result.fail(502, 'Unable to connect to the MCP server.');
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
      final skillIds = _skillIds(data);
      if (utf8.encode(input).length > 32 * 1024) {
        return Result.fail(400, 'Input is too large.');
      }
      final targetKey = _targetKey(connectionId);
      if (_repository.getConversation(id, targetKey) == null) {
        return Result.fail(404, 'Conversation not found.');
      }
      final skills = await _skillService.snapshot(connectionId, skillIds);
      final run = _runManager.start(
        conversationId: id,
        connectionId: connectionId,
        targetKey: targetKey,
        ownerId: _principalId(request),
        input: input,
        skills: skills,
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

  String _mcpName(Map<String, dynamic> data) {
    final name = _requiredString(data, 'name').trim();
    if (name.length > 60) {
      throw const FormatException('MCP server name is too long.');
    }
    return name;
  }

  String _mcpUrl(Map<String, dynamic> data) {
    final value = _requiredString(data, 'url').trim();
    if (value.length > 2048) {
      throw const FormatException('MCP server URL is too long.');
    }
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !uri.hasAuthority ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.userInfo.isNotEmpty ||
        uri.fragment.isNotEmpty) {
      throw const FormatException(
        'MCP server URL must be a valid HTTP or HTTPS URL.',
      );
    }
    return uri.toString();
  }

  Map<String, String>? _mcpHeaders(Map<String, dynamic> data) {
    if (!data.containsKey('headers')) return null;
    final value = data['headers'];
    if (value is! Map<String, dynamic> ||
        value.length > 20 ||
        value.entries.any(
          (entry) =>
              entry.key.trim().isEmpty ||
              entry.key.length > 100 ||
              !RegExp(
                r'^[A-Za-z0-9!#$%&\x27*+.^_`|~-]+$',
              ).hasMatch(entry.key) ||
              _reservedMcpHeaders.contains(entry.key.toLowerCase()) ||
              entry.value is! String ||
              (entry.value as String).length > 4096 ||
              (entry.value as String).contains(RegExp(r'[\r\n]')),
        )) {
      throw const FormatException(
        'MCP headers must be a string-to-string object.',
      );
    }
    return Map.unmodifiable(
      value.map((key, value) => MapEntry(key.trim(), value as String)),
    );
  }

  static const _reservedMcpHeaders = {
    'accept',
    'connection',
    'content-length',
    'content-type',
    'host',
    'mcp-protocol-version',
    'mcp-session-id',
    'transfer-encoding',
  };

  List<String> _skillIds(Map<String, dynamic> data) {
    if (!data.containsKey('skillIds')) return const [];
    final value = data['skillIds'];
    if (value is! List ||
        value.any((item) => item is! String || item.isEmpty)) {
      throw const FormatException('skillIds must be an array of strings.');
    }
    if (value.length > AiAgentSkillService.maxSelectedSkills) {
      throw const FormatException('At most 8 skills may be selected.');
    }
    return List<String>.unmodifiable(value.cast<String>());
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
