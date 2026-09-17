import 'dart:convert';
import 'dart:io';

import 'package:host_deck/server/features/ai_agent/ai_agent_models.dart';
import 'package:host_deck/server/features/ai_agent/ai_agent_repository.dart';
import 'package:host_deck/server/features/ai_agent/ai_agent_secret_store.dart';

class AiAgentResolvedSettings {
  final String baseUrl;
  final String model;
  final String apiKey;

  const AiAgentResolvedSettings({
    required this.baseUrl,
    required this.model,
    required this.apiKey,
  });
}

class AiAgentSettingsService {
  final AiAgentRepository _repository;
  final AiAgentSecretStore _secretStore;

  AiAgentSettingsService(this._repository, this._secretStore);

  AiAgentSettings get() {
    final stored = _repository.getSettings();
    return AiAgentSettings(
      baseUrl: stored.baseUrl,
      model: stored.model,
      models: _configuredModels(stored),
      hasApiKey: stored.encryptedApiKey?.isNotEmpty == true,
    );
  }

  AiAgentSettings update({
    String? baseUrl,
    String? model,
    List<AiAgentModelConfig>? models,
    String? apiKey,
    bool clearApiKey = false,
  }) {
    final current = _repository.getSettings();
    final nextBaseUrl = baseUrl == null
        ? current.baseUrl
        : _validateBaseUrl(baseUrl);
    final nextModel = model == null ? current.model : _validateModel(model);
    final nextModels = _configuredModels(current, models: models);
    if (!nextModels.any((item) => item.id == nextModel)) {
      nextModels.add(AiAgentModelConfig(id: nextModel, name: nextModel));
    }
    final endpointChanged = nextBaseUrl != current.baseUrl;
    String? encryptedApiKey = current.encryptedApiKey;
    if (clearApiKey) {
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
        baseUrl: nextBaseUrl,
        model: nextModel,
        models: nextModels,
        encryptedApiKey: encryptedApiKey,
      ),
    );
    return get();
  }

  AiAgentResolvedSettings resolve({
    String? baseUrl,
    String? model,
    String? apiKey,
  }) {
    final stored = _repository.getSettings();
    final resolvedBaseUrl = baseUrl == null
        ? stored.baseUrl
        : _validateBaseUrl(baseUrl);
    if (baseUrl != null &&
        resolvedBaseUrl != stored.baseUrl &&
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
      baseUrl: resolvedBaseUrl,
      model: model == null ? stored.model : _validateModel(model),
      apiKey: resolvedKey,
    );
  }

  Future<List<String>> listModels() async {
    final settings = resolve();
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
