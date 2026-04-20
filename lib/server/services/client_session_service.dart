import 'dart:math';

import 'package:shelf/shelf.dart';

class ClientSession {
  final String clientId;
  final bool isNew;

  const ClientSession({required this.clientId, required this.isNew});
}

class ClientSessionService {
  static const cookieName = 'ssh_tool_client_id';

  final Random _random = Random.secure();

  ClientSession resolve(Request request) {
    final cookies = request.headers['cookie'];
    final cookieMap = _parseCookies(cookies);
    final clientId = cookieMap[cookieName];

    if (clientId != null && clientId.isNotEmpty) {
      return ClientSession(clientId: clientId, isNew: false);
    }

    return ClientSession(clientId: _generateClientId(), isNew: true);
  }

  Map<String, String> buildSessionHeaders(ClientSession session) {
    if (!session.isNew) {
      return const {};
    }

    return {
      'set-cookie':
          '${cookieName}=${session.clientId}; Path=/; HttpOnly; SameSite=Lax',
    };
  }

  Map<String, String> _parseCookies(String? header) {
    if (header == null || header.isEmpty) {
      return const {};
    }

    final cookies = <String, String>{};
    for (final part in header.split(';')) {
      final index = part.indexOf('=');
      if (index <= 0) {
        continue;
      }

      final key = part.substring(0, index).trim();
      final value = part.substring(index + 1).trim();
      if (key.isNotEmpty) {
        cookies[key] = value;
      }
    }

    return cookies;
  }

  String _generateClientId() {
    const alphabet =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final buffer = StringBuffer();
    for (var index = 0; index < 32; index++) {
      buffer.write(alphabet[_random.nextInt(alphabet.length)]);
    }

    return buffer.toString();
  }
}
