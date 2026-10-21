import 'package:host_deck/server/core/ssh/ssh_connection_handle.dart';

/// A POSIX shell invocation used to wrap a remote script.
///
/// Some servers ship a `~/.profile` that only a real bash can source (for
/// example `swiftly/env.sh` uses `${PATH//...}`). When `/bin/sh` is dash, a
/// login shell dies while reading the profile and never runs the script, so the
/// invocation has to be picked per connection instead of hard-coding `sh -lc`.
class ShellInvocation {
  final String prefix;

  const ShellInvocation(this.prefix);

  static const ShellInvocation plain = ShellInvocation('sh -c');

  bool get loadsProfile => prefix.endsWith('-lc');

  String wrap(String script) => '$prefix ${quote(script)}';

  static String quote(String value) => "'${value.replaceAll("'", "'\\''")}'";

  @override
  String toString() => prefix;
}

/// Picks the first working shell invocation for a connection and caches it.
class ShellInvocationResolver {
  static const List<String> candidates = ['sh -lc', 'bash -lc', 'sh -c'];

  final Map<String, ShellInvocation> _resolved = {};
  final Map<String, Future<ShellInvocation>> _pending = {};

  ShellInvocation? cached(String connectionId) => _resolved[connectionId];

  Future<ShellInvocation> resolve(SshOperationContext session) {
    final connectionId = session.connectionId;
    final cachedInvocation = _resolved[connectionId];
    if (cachedInvocation != null) {
      return Future.value(cachedInvocation);
    }

    final pendingInvocation = _pending[connectionId];
    if (pendingInvocation != null) {
      return pendingInvocation;
    }

    late final Future<ShellInvocation> next;
    next = _probe(session)
        .then((probed) {
          if (probed == null) {
            // No candidate even started, which usually means the connection is
            // gone rather than the profile being broken. Run this one command
            // through a plain shell, but do not cache the guess: the next call
            // probes again instead of pinning a profile-less shell forever.
            return ShellInvocation.plain;
          }
          // Only store the result while this probe is still the current one, so
          // an invalidation (or a newer probe) made mid-flight cannot be
          // overwritten by the stale outcome.
          if (identical(_pending[connectionId], next)) {
            _resolved[connectionId] = probed;
          }
          return probed;
        })
        .whenComplete(() {
          if (identical(_pending[connectionId], next)) {
            _pending.remove(connectionId);
          }
        });

    _pending[connectionId] = next;
    return next;
  }

  /// Drops the cached result so the next [resolve] probes the server again.
  void invalidate(String connectionId) {
    _resolved.remove(connectionId);
    _pending.remove(connectionId);
  }

  /// Returns the first invocation whose probe exited cleanly, or null when no
  /// candidate could even be started.
  Future<ShellInvocation?> _probe(SshOperationContext session) async {
    for (final prefix in candidates) {
      final invocation = ShellInvocation(prefix);
      try {
        final result = await session.runOperation(
          () => session.client.runWithResult(invocation.wrap(':')),
        );
        if ((result.exitCode ?? 1) == 0) {
          return invocation;
        }
      } catch (_) {
        // Try the next candidate; the caller decides what a total failure means.
      }
    }

    return null;
  }
}
