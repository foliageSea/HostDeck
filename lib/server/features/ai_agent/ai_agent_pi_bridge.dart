import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Private NDJSON IPC. Credentials are sent on stdin, never in process arguments.
class AiAgentPiBridge {
  Process? _process;
  bool _closed = false;

  static bool _isJavaScript(String path) =>
      path.endsWith('.mjs') || path.endsWith('.js');

  static String _nodeExecutable(String script) {
    final bundledNode = p.join(
      p.dirname(script),
      Platform.isWindows ? 'node.exe' : 'node',
    );
    return Platform.environment['HOSTDECK_AI_NODE'] ??
        (File(bundledNode).existsSync() ? bundledNode : 'node');
  }

  static String _bridgePath() {
    final configured = Platform.environment['HOSTDECK_AI_BRIDGE'];
    final binaryName = Platform.isWindows ? 'bridge.exe' : 'bridge';
    final candidates = [
      ?configured,
      p.join(p.dirname(Platform.resolvedExecutable), '..', 'ai', binaryName),
      p.join(p.dirname(Platform.resolvedExecutable), '..', 'ai', 'bridge.mjs'),
      p.join(Directory.current.path, 'host-deck-ai', 'dist', 'bridge.mjs'),
      p.join(Directory.current.path, 'host-deck-ai', 'dist', binaryName),
    ];
    for (final candidate in candidates) {
      if (File(candidate).existsSync()) return p.normalize(candidate);
    }
    throw StateError(
      'pi-ai bridge is missing. Run pnpm install and pnpm run build:bin (or build) in host-deck-ai.',
    );
  }

  Future<Map<String, dynamic>> request(
    Map<String, dynamic> payload, {
    void Function(String)? onTextDelta,
    void Function(String)? onThinkingDelta,
    void Function()? onThinkingEnd,
    void Function(Map<String, dynamic>)? onAuth,
    Duration timeout = const Duration(minutes: 2),
  }) async {
    if (_closed) throw StateError('Model request was cancelled.');
    final bridge = _bridgePath();
    final isScript = _isJavaScript(bridge);
    final executable = isScript ? _nodeExecutable(bridge) : bridge;
    Process process;
    try {
      process = await Process.start(executable, isScript ? [bridge] : const []);
    } on ProcessException {
      throw StateError(
        isScript
            ? 'Unable to start pi-ai. Install Node.js >=22.19 or set HOSTDECK_AI_NODE.'
            : 'Unable to start pi-ai bridge. Rebuild host-deck-ai or check executable permissions.',
      );
    }
    _process = process;
    if (_closed) {
      process.kill();
      throw StateError('Model request was cancelled.');
    }
    // Drain stderr without forwarding SDK output that might contain secrets.
    final errors = process.stderr.drain<void>();
    final input = Future<void>(() async {
      process.stdin.writeln(jsonEncode(payload));
      await process.stdin.close();
    });
    // Attach an error handler immediately: early process exit may break stdin.
    final inputDone = input.then<Object?>(
      (_) => null,
      onError: (Object error) => error,
    );
    Map<String, dynamic>? result;
    try {
      await for (final line
          in process.stdout
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .timeout(timeout)) {
        final event = jsonDecode(line) as Map<String, dynamic>;
        switch (event['type']) {
          case 'text':
            onTextDelta?.call(event['text'] as String);
          case 'thinking':
            onThinkingDelta?.call(event['text'] as String);
          case 'thinking-end':
            onThinkingEnd?.call();
          case 'auth':
            onAuth?.call(event);
          case 'result':
            result = event;
          case 'error':
            throw StateError(event['message'] as String);
          default:
            throw const FormatException('Invalid pi-ai bridge event.');
        }
      }
      final exitCode = await process.exitCode.timeout(
        const Duration(seconds: 5),
      );
      final inputError = await inputDone;
      if (_closed) throw StateError('Model request was cancelled.');
      if (exitCode != 0 || result == null || inputError != null) {
        throw StateError(
          'pi-ai bridge exited without a valid response. Check its build and runtime compatibility.',
        );
      }
      return result;
    } finally {
      process.kill();
      await errors;
      _process = null;
    }
  }

  void close() {
    _closed = true;
    _process?.kill();
  }
}
