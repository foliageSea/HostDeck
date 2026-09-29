import 'dart:convert';
import 'dart:io';

import 'package:host_deck/server/features/ai_agent/ai_agent_models.dart';
import 'package:host_deck/server/features/ai_agent/ai_agent_repository.dart';
import 'package:host_deck/server/features/ai_agent/ai_agent_secret_store.dart';
import 'package:host_deck/server/features/ai_agent/ai_agent_pi_bridge.dart';
import 'package:host_deck/server/features/ai_agent/ai_agent_oauth_service.dart';

class AiAgentResolvedSettings {
  final String provider;
  final String api;
  final String baseUrl;
  final String model;
  final String apiKey;
  final Future<Map<String, dynamic>> Function()? oauthCredential;

  const AiAgentResolvedSettings({
    this.oauthCredential,
    this.provider = 'custom',
    this.api = 'openai-completions',
    required this.baseUrl,
    required this.model,
    required this.apiKey,
  });
}

class AiAgentSettingsService {
  late final AiAgentOAuthService oauth = AiAgentOAuthService(
    _repository,
    _secretStore,
  );
  final AiAgentRepository _repository;
  final AiAgentSecretStore _secretStore;

  AiAgentSettingsService(this._repository, this._secretStore);

  AiAgentSettings get() {
    final stored = _repository.getSettings();
    return AiAgentSettings(
      provider: stored.provider,
      api: stored.api,
      baseUrl: stored.baseUrl,
      model: stored.model,
      models: _configuredModels(stored),
      hasApiKey: stored.encryptedApiKey?.isNotEmpty == true,
      hasOAuth: oauth.authenticated,
      showRemoteSkills: stored.showRemoteSkills,
    );
  }

  AiAgentSettings update({
    String? provider,
    String? api,
    String? baseUrl,
    String? model,
    List<AiAgentModelConfig>? models,
    String? apiKey,
    bool clearApiKey = false,
    bool? showRemoteSkills,
  }) {
    final current = _repository.getSettings();
    final nextProvider = provider == null
        ? current.provider
        : _validateProvider(provider);
    final requestedApi = api == null ? current.api : _validateApi(api);
    final nextApi = nextProvider == 'openai-codex'
        ? 'openai-codex-responses'
        : requestedApi;
    final nextBaseUrl = baseUrl == null
        ? current.baseUrl
        : _validateBaseUrl(baseUrl);
    final nextModel = model == null ? current.model : _validateModel(model);
    if (nextProvider == 'openai-codex') {
      _validateCodexEndpoint(nextBaseUrl);
    } else if (nextApi == 'openai-codex-responses') {
      throw const FormatException('Codex requires the OpenAI Codex provider.');
    }
    final nextModels = _configuredModels(current, models: models);
    if (!nextModels.any((item) => item.id == nextModel)) {
      nextModels.add(AiAgentModelConfig(id: nextModel, name: nextModel));
    }
    final endpointChanged =
        nextBaseUrl != current.baseUrl || nextProvider != current.provider;
    String? encryptedApiKey = current.encryptedApiKey;
    if (clearApiKey || nextProvider == 'openai-codex') {
      encryptedApiKey = null;
    } else if (apiKey != null && apiKey.isNotEmpty) {
      encryptedApiKey = _secretStore.encrypt(_validateApiKey(apiKey));
    } else if (endpointChanged && encryptedApiKey != null) {
      throw const FormatException(
        'Changing baseUrl requires a new API key or clearApiKey.',
      );
    }
    _repository.saveSettings(
      AiAgentStoredSettings(
        provider: nextProvider,
        api: nextApi,
        baseUrl: nextBaseUrl,
        model: nextModel,
        models: nextModels,
        encryptedApiKey: encryptedApiKey,
        showRemoteSkills: showRemoteSkills ?? current.showRemoteSkills,
      ),
    );
    return get();
  }

  AiAgentResolvedSettings resolve({
    String? provider,
    String? api,
    String? baseUrl,
    String? model,
    String? apiKey,
  }) {
    final stored = _repository.getSettings();
    final resolvedProvider = provider == null
        ? stored.provider
        : _validateProvider(provider);
    final resolvedApi = api == null ? stored.api : _validateApi(api);
    final resolvedBaseUrl = baseUrl == null
        ? stored.baseUrl
        : _validateBaseUrl(baseUrl);
    if (resolvedProvider == 'openai-codex') {
      _validateCodexEndpoint(resolvedBaseUrl);
      if (!oauth.authenticated) throw StateError('请先登录 OpenAI Codex。');
      return AiAgentResolvedSettings(
        provider: resolvedProvider,
        api: 'openai-codex-responses',
        baseUrl: resolvedBaseUrl,
        model: model == null ? stored.model : _validateModel(model),
        apiKey: '',
        oauthCredential: oauth.credential,
      );
    }
    if ((resolvedBaseUrl != stored.baseUrl ||
            resolvedProvider != stored.provider) &&
        (apiKey == null || apiKey.isEmpty)) {
      throw const FormatException(
        'Testing a different baseUrl requires an explicit API key.',
      );
    }
    final resolvedKey = apiKey != null && apiKey.isNotEmpty
        ? _validateApiKey(apiKey)
        : stored.encryptedApiKey == null
        ? ''
        : _secretStore.decrypt(stored.encryptedApiKey!);
    if (resolvedKey.isEmpty) {
      throw StateError('API key is not configured.');
    }
    return AiAgentResolvedSettings(
      provider: resolvedProvider,
      api: resolvedApi,
      baseUrl: resolvedBaseUrl,
      model: model == null ? stored.model : _validateModel(model),
      apiKey: resolvedKey,
    );
  }

  Future<List<String>> listModels() async {
    final stored = _repository.getSettings();
    if (stored.provider != 'custom') {
      final providers = await catalog();
      final provider = providers
          .where((item) => item['id'] == stored.provider)
          .firstOrNull;
      if (provider == null) throw StateError('Provider is not supported.');
      return (provider['models'] as List)
          .map((model) => model['id'] as String)
          .toList();
    }
    final settings = resolve();
    if (settings.api != 'openai-completions' &&
        settings.api != 'openai-responses') {
      throw StateError('Enter model IDs manually for this custom API.');
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client
          .getUrl(Uri.parse('${settings.baseUrl}/models'))
          .timeout(const Duration(seconds: 15));
      request.headers
        ..set(HttpHeaders.authorizationHeader, 'Bearer ${settings.apiKey}')
        ..set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('Unable to fetch the configured model list.');
      }
      final body = await utf8.decoder.bind(response).join();
      final decoded = jsonDecode(body);
      if (decoded is! Map || decoded['data'] is! List) {
        throw const FormatException('Model list response is invalid.');
      }
      final models = <String>{
        for (final item in decoded['data'] as List)
          if (item is Map && item['id'] is String)
            _validateModel(item['id'] as String),
      }.toList()..sort();
      return models;
    } finally {
      client.close(force: true);
    }
  }

  String _validateBaseUrl(String value) {
    final normalized = value.trim();
    if (normalized.length > 2048) {
      throw const FormatException('baseUrl is too long.');
    }
    final uri = Uri.tryParse(normalized);
    if (uri == null ||
        !uri.hasAuthority ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        uri.hasQuery ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw FormatException('baseUrl must be an absolute HTTP(S) URL.');
    }
    return normalized.replaceFirst(RegExp(r'/+$'), '');
  }

  String _validateModel(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty || normalized.length > 200) {
      throw FormatException('model must not be empty.');
    }
    return normalized;
  }

  Future<List<Map<String, dynamic>>> catalog() async {
    final bridge = AiAgentPiBridge();
    try {
      final result = await bridge.request({'type': 'catalog'});
      return (result['providers'] as List).cast<Map<String, dynamic>>();
    } finally {
      bridge.close();
    }
  }

  String _validateProvider(String value) {
    if (!RegExp(r'^[a-z0-9][a-z0-9-]{0,99}$').hasMatch(value)) {
      throw const FormatException('Invalid provider.');
    }
    return value;
  }

  String _validateApi(String value) {
    if (!{
      'openai-completions',
      'openai-responses',
      'anthropic-messages',
      'google-generative-ai',
      'openai-codex-responses',
    }.contains(value)) {
      throw const FormatException('Unsupported model API.');
    }
    return value;
  }

  void _validateCodexEndpoint(String value) {
    if (value != 'https://chatgpt.com/backend-api') {
      throw const FormatException(
        'OpenAI Codex uses https://chatgpt.com/backend-api.',
      );
    }
  }

  String _validateApiKey(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty || normalized.length > 8192) {
      throw const FormatException('apiKey is invalid.');
    }
    return normalized;
  }

  List<AiAgentModelConfig> _configuredModels(
    AiAgentStoredSettings settings, {
    List<AiAgentModelConfig>? models,
  }) {
    final values =
        models ??
        [
          ...settings.models,
          AiAgentModelConfig(id: settings.model, name: settings.model),
        ];
    if (values.length > 100) {
      throw const FormatException('At most 100 models may be configured.');
    }
    final unique = <String, AiAgentModelConfig>{};
    for (final value in values) {
      final id = _validateModel(value.id);
      final name = _validateModel(value.name);
      unique[id] = AiAgentModelConfig(id: id, name: name);
    }
    return unique.values.toList()..sort((a, b) => a.id.compareTo(b.id));
  }
}
