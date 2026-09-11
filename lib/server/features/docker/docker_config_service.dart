import 'dart:convert';

import 'package:host_deck/server/core/ssh/ssh_repository.dart';
import 'package:host_deck/server/core/ssh/ssh_session.dart';
import 'package:host_deck/server/features/docker/docker_registry_repository.dart';
import 'package:host_deck/server/features/docker/docker_registry_setting.dart';

class DockerConfigService {
  final SshRepository _sshRepository;
  final DockerRegistryRepository _registryRepository;

  DockerConfigService(this._sshRepository, this._registryRepository);

  Future<Map<String, dynamic>> getConfiguration(SshSession session) async {
    final daemon = await _readDaemonConfig(session);
    final targetKey = await _resolveTargetKey(session);
    final proxies = daemon['proxies'] is Map
        ? Map<String, dynamic>.from(daemon['proxies'] as Map)
        : const <String, dynamic>{};
    final mirrors = daemon['registry-mirrors'] is List
        ? (daemon['registry-mirrors'] as List)
              .map((value) => value.toString())
              .toList()
        : <String>[];
    final proxyEnabled = proxies.values.any(
      (value) => value?.toString().trim().isNotEmpty == true,
    );

    return {
      'mirrors': mirrors,
      'proxy': {
        'enabled': proxyEnabled,
        'httpProxy': proxies['http-proxy']?.toString() ?? '',
        'httpsProxy': proxies['https-proxy']?.toString() ?? '',
        'noProxy': proxies['no-proxy']?.toString() ?? '',
      },
      'registries': _registryRepository
          .list(targetKey)
          .map((setting) => setting.toJson())
          .toList(),
    };
  }

  Future<Map<String, dynamic>> updateDaemonConfig(
    SshSession session,
    Map<String, dynamic> payload,
  ) async {
    final hasMirrors = payload.containsKey('mirrors');
    final hasProxy = payload.containsKey('proxy');
    if (!hasMirrors && !hasProxy) {
      throw ArgumentError('至少需要提供一项 Docker 配置。');
    }
    final mirrors = _stringList(payload['mirrors']);
    if (hasMirrors) {
      for (final mirror in mirrors) {
        final uri = Uri.tryParse(mirror);
        if (uri == null ||
            !uri.hasAuthority ||
            (uri.scheme != 'http' && uri.scheme != 'https')) {
          throw ArgumentError('镜像加速地址必须是有效的 HTTP 或 HTTPS URL。');
        }
      }
    }

    final proxyPayload = payload['proxy'];
    if (hasProxy && proxyPayload is! Map) {
      throw ArgumentError('Docker 代理配置格式无效。');
    }
    final proxy = proxyPayload is Map
        ? Map<String, dynamic>.from(proxyPayload)
        : <String, dynamic>{};
    final enabled = proxy['enabled'] == true;
    final httpProxy = proxy['httpProxy']?.toString().trim() ?? '';
    final httpsProxy = proxy['httpsProxy']?.toString().trim() ?? '';
    final noProxy = proxy['noProxy']?.toString().trim() ?? '';
    if (hasProxy && enabled && httpProxy.isEmpty && httpsProxy.isEmpty) {
      throw ArgumentError('启用 Docker 代理后，HTTP 代理和 HTTPS 代理至少填写一项。');
    }
    if (hasProxy) {
      for (final value in [httpProxy, httpsProxy]) {
        if (value.isEmpty) continue;
        final uri = Uri.tryParse(value);
        if (uri == null ||
            !uri.hasAuthority ||
            !{'http', 'https'}.contains(uri.scheme)) {
          throw ArgumentError('代理地址必须是有效的 HTTP 或 HTTPS URL。');
        }
      }
    }

    final daemon = await _readDaemonConfig(session);
    if (hasMirrors) {
      if (mirrors.isEmpty) {
        daemon.remove('registry-mirrors');
      } else {
        daemon['registry-mirrors'] = mirrors;
      }
    }
    if (hasProxy) {
      if (!enabled) {
        daemon.remove('proxies');
      } else {
        daemon['proxies'] = {
          if (httpProxy.isNotEmpty) 'http-proxy': httpProxy,
          if (httpsProxy.isNotEmpty) 'https-proxy': httpsProxy,
          if (noProxy.isNotEmpty) 'no-proxy': noProxy,
        };
      }
    }

    final content = '${const JsonEncoder.withIndent('  ').convert(daemon)}\n';
    final write = await _sshRepository.execWithResult(session, '''tmp=\$(mktemp)
cat > "\$tmp"
if [ "\$(id -u)" -eq 0 ]; then
  install -d -m 0755 /etc/docker && install -m 0644 "\$tmp" /etc/docker/daemon.json
else
  sudo -n install -d -m 0755 /etc/docker && sudo -n install -m 0644 "\$tmp" /etc/docker/daemon.json
fi
status=\$?
rm -f "\$tmp"
exit \$status''', stdin: content);
    _ensureSuccess(write, '无法写入 /etc/docker/daemon.json');

    final restart = await _sshRepository.execWithResult(
      session,
      '''if [ "\$(id -u)" -eq 0 ]; then
  systemctl daemon-reload && systemctl restart docker
else
  sudo -n systemctl daemon-reload && sudo -n systemctl restart docker
fi''',
      timeout: const Duration(minutes: 2),
    );
    _ensureSuccess(restart, 'Docker 配置已写入，但服务重启失败');
    return getConfiguration(session);
  }

  Future<List<Map<String, dynamic>>> updateRegistries(
    SshSession session,
    dynamic payload,
  ) async {
    if (payload is! List) throw ArgumentError('registries must be a list');
    final targetKey = await _resolveTargetKey(session);
    final existing = {
      for (final item in _registryRepository.list(targetKey))
        item.address: item,
    };
    final settings = <DockerRegistrySetting>[];
    final addresses = <String>{};
    for (final raw in payload) {
      if (raw is! Map) throw ArgumentError('镜像仓库配置格式无效。');
      final item = Map<String, dynamic>.from(raw);
      final address = item['address']?.toString().trim() ?? '';
      final name = item['name']?.toString().trim() ?? '';
      final namespace = item['namespace']?.toString().trim() ?? '';
      final authentication = item['authentication'] == true;
      final username = item['username']?.toString().trim() ?? '';
      final password = item['password']?.toString() ?? '';
      if (address.isEmpty || name.isEmpty) {
        throw ArgumentError('仓库地址和仓库名称不能为空。');
      }
      if (!addresses.add(address)) throw ArgumentError('仓库地址不能重复。');
      if (authentication && username.isEmpty) {
        throw ArgumentError('启用认证后必须填写用户名。');
      }
      final previous = existing[address];
      if (authentication &&
          password.isEmpty &&
          (previous == null || previous.username != username)) {
        throw ArgumentError('新增认证仓库或修改用户名时必须填写密码。');
      }
      if (authentication && password.isNotEmpty) {
        final login = await _sshRepository.execWithResult(
          session,
          'docker login ${_shellQuote(address)} --username ${_shellQuote(username)} --password-stdin',
          stdin: password,
          timeout: const Duration(minutes: 1),
        );
        _ensureSuccess(login, '登录镜像仓库 $name 失败');
      }
      settings.add(
        DockerRegistrySetting(
          targetKey: targetKey,
          address: address,
          name: name,
          namespace: namespace,
          authentication: authentication,
          username: authentication ? username : '',
        ),
      );
    }
    return _registryRepository
        .replaceAll(targetKey, settings)
        .map((setting) => setting.toJson())
        .toList();
  }

  Future<Map<String, dynamic>> _readDaemonConfig(SshSession session) async {
    final result = await _sshRepository.execWithResult(
      session,
      '''if [ ! -e /etc/docker/daemon.json ]; then
  printf '{}'
elif [ -r /etc/docker/daemon.json ]; then
  cat /etc/docker/daemon.json
elif command -v sudo >/dev/null 2>&1; then
  sudo -n cat /etc/docker/daemon.json
else
  exit 1
fi''',
    );
    _ensureSuccess(result, '无法读取 /etc/docker/daemon.json');
    try {
      final decoded = jsonDecode(
        result.stdout.trim().isEmpty ? '{}' : result.stdout,
      );
      if (decoded is! Map) throw const FormatException();
      return Map<String, dynamic>.from(decoded);
    } on FormatException {
      throw StateError('/etc/docker/daemon.json 不是有效的 JSON，已停止修改。');
    }
  }

  Future<String> _resolveTargetKey(SshSession session) async {
    final result = await _sshRepository.execWithResult(
      session,
      '''machine=\$(cat /etc/machine-id 2>/dev/null || hostname)
printf '%s:%s' "\$machine" "\$(id -un)"''',
    );
    _ensureSuccess(result, '无法识别远端 Docker 配置所属主机');
    final key = result.stdout.trim();
    if (key.isEmpty) throw StateError('无法识别远端 Docker 配置所属主机。');
    return key;
  }

  List<String> _stringList(dynamic value) {
    if (value is! List) return <String>[];
    return value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList();
  }

  void _ensureSuccess(dynamic result, String message) {
    if (result.exitCode == 0) return;
    final detail = result.stderr.toString().trim().isNotEmpty
        ? result.stderr.toString().trim()
        : result.stdout.toString().trim();
    throw StateError(detail.isEmpty ? message : '$message：$detail');
  }

  String _shellQuote(String value) => "'${value.replaceAll("'", "'\\''")}'";
}
