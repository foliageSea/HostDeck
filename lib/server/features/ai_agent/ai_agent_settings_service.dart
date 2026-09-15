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
      hasApiKey: stored.encryptedApiKey?.isNotEmpty == true,
    );
  }

  AiAgentSettings update({
    String? baseUrl,
    String? model,
    String? apiKey,
    bool clearApiKey = false,
  }) {
    final current = _repository.getSettings();
    final nextBaseUrl = baseUrl == null
        ? current.baseUrl
        : _validateBaseUrl(baseUrl);
    final nextModel = model == null ? current.model : _validateModel(model);
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
}
