import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:host_deck/server/features/ai_agent/ai_agent_pi_bridge.dart';
import 'package:host_deck/server/features/ai_agent/ai_agent_repository.dart';
import 'package:host_deck/server/features/ai_agent/ai_agent_secret_store.dart';

/// Owns credential writes and serializes refreshes across concurrent runs.
/// Node processes receive snapshots; they never refresh or persist on their own.
class AiAgentOAuthService {
  static const provider = 'openai-codex';
  final AiAgentRepository _repository;
  final AiAgentSecretStore _secrets;
  final AiAgentPiBridge Function() _bridgeFactory;
  AiAgentPiBridge? _loginBridge;
  AiAgentPiBridge? _refreshBridge;
  Future<Map<String, dynamic>>? _refresh;
  Timer? _loginTimer;
  int _generation = 0;
  Map<String, dynamic> _login = {'status': 'idle'};

  AiAgentOAuthService(
    this._repository,
    this._secrets, {
    AiAgentPiBridge Function()? bridgeFactory,
  }) : _bridgeFactory = bridgeFactory ?? AiAgentPiBridge.new;

  bool get authenticated => _repository.getCredential(provider) != null;

  Map<String, dynamic> status() => {'authenticated': authenticated, ..._login};

  Map<String, dynamic> startLogin() {
    _cancelLogin();
    final id = base64UrlEncode(
      List.generate(24, (_) => Random.secure().nextInt(256)),
    );
    final bridge = _bridgeFactory();
    _loginBridge = bridge;
    _login = {'id': id, 'status': 'starting'};
    _loginTimer = Timer(const Duration(minutes: 15), () {
      if (_loginBridge != bridge) return;
      _cancelLogin();
      _login = {'id': id, 'status': 'expired', 'error': '登录已过期，请重新获取设备码。'};
    });
    unawaited(_loginWithBridge(bridge, id));
    return status();
  }

  Future<void> _loginWithBridge(AiAgentPiBridge bridge, String id) async {
    try {
      final result = await bridge.request(
        {'type': 'oauth-login'},
        timeout: const Duration(minutes: 15),
        onAuth: (event) {
          if (_loginBridge != bridge) return;
          final uri = Uri.tryParse(event['verificationUri'] as String? ?? '');
          if (uri?.scheme != 'https' || uri?.host != 'auth.openai.com') {
            throw const FormatException('Invalid OAuth verification URL.');
          }
          _login = {
            'id': id,
            'status': 'pending',
            'userCode': event['userCode'] as String,
            'verificationUri': uri.toString(),
            'expiresAt':
                DateTime.now().millisecondsSinceEpoch +
                ((event['expiresInSeconds'] as num?)?.toInt() ?? 900).clamp(
                      1,
                      900,
                    ) *
                    1000,
          };
        },
      );
      if (_loginBridge != bridge) return;
      final credential = _validate(result['credential']);
      // A late refresh must not overwrite a newly signed-in account.
      _generation++;
      _refreshBridge?.close();
      _repository.saveCredential(
        provider,
        _secrets.encrypt(jsonEncode(credential)),
      );
      _login = {'id': id, 'status': 'success'};
    } catch (_) {
      if (_loginBridge == bridge) {
        _login = {
          'id': id,
          'status': 'failed',
          'error': 'OpenAI 登录失败，请检查网络及账号的设备码登录设置后重试。',
        };
      }
    } finally {
      bridge.close();
      if (_loginBridge == bridge) {
        _loginBridge = null;
        _loginTimer?.cancel();
      }
    }
  }

  void cancelLogin(String id) {
    if (_login['id'] != id) return;
    _cancelLogin();
    _login = {'id': id, 'status': 'cancelled'};
  }

  void _cancelLogin() {
    _loginTimer?.cancel();
    _loginBridge?.close();
    _loginBridge = null;
  }

  void logout() {
    _generation++;
    _cancelLogin();
    _refreshBridge?.close();
    _repository.deleteCredential(provider);
    _login = {'status': 'idle'};
  }

  Future<Map<String, dynamic>> credential() async {
    final encrypted = _repository.getCredential(provider);
    if (encrypted == null) throw StateError('请先登录 OpenAI Codex。');
    final current = _validate(jsonDecode(_secrets.decrypt(encrypted)));
    if ((current['expires'] as num) >
        DateTime.now().millisecondsSinceEpoch + 60000) {
      return current;
    }
    final pending = _refresh;
    if (pending != null) return pending;
    final future = _refreshCredential(current, encrypted, _generation);
    _refresh = future;
    try {
      return await future;
    } finally {
      if (identical(_refresh, future)) _refresh = null;
    }
  }

  Future<Map<String, dynamic>> _refreshCredential(
    Map<String, dynamic> current,
    String encrypted,
    int generation,
  ) async {
    final bridge = _bridgeFactory();
    _refreshBridge = bridge;
    try {
      final result = await bridge.request({
        'type': 'oauth-refresh',
        'credential': current,
      });
      if (generation != _generation ||
          _repository.getCredential(provider) != encrypted) {
        throw StateError('OAuth credentials changed during refresh.');
      }
      final refreshed = _validate(result['credential']);
      _repository.saveCredential(
        provider,
        _secrets.encrypt(jsonEncode(refreshed)),
      );
      return refreshed;
    } catch (_) {
      // Preserve the saved credential on transient failures; never fall back to
      // an API key or silently restore credentials after logout.
      throw StateError('OpenAI 登录凭据刷新失败，请重试或重新登录。');
    } finally {
      bridge.close();
      if (_refreshBridge == bridge) _refreshBridge = null;
    }
  }

  Map<String, dynamic> _validate(dynamic value) {
    if (value is! Map<String, dynamic> ||
        value['type'] != 'oauth' ||
        value['access'] is! String ||
        (value['access'] as String).isEmpty ||
        value['refresh'] is! String ||
        (value['refresh'] as String).isEmpty ||
        value['expires'] is! num) {
      throw const FormatException('Invalid OAuth credential.');
    }
    return value;
  }

  void dispose() {
    _generation++;
    _cancelLogin();
    _refreshBridge?.close();
  }
}
