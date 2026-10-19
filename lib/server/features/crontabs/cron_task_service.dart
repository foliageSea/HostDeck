import 'dart:async';

import 'package:host_deck/server/core/ssh/ssh_repository.dart';
import 'package:host_deck/server/core/ssh/ssh_session.dart';
import 'package:host_deck/server/features/crontabs/cron_task.dart';
import 'package:host_deck/server/features/crontabs/cron_task_repository.dart';

class CronTaskService {
  static const _baseDir = r'$HOME/.hostdeck/cron';
  final SshRepository _sshRepository;
  final CronTaskRepository _repository;
  final Map<int, Future<void>> _serverLocks = {};

  CronTaskService(this._sshRepository, this._repository);

  /// Serializes crontab read-modify-write cycles per saved server so concurrent
  /// UI and agent requests cannot overwrite each other's changes.
  Future<T> _serialized<T>(int serverId, Future<T> Function() action) {
    final previous = _serverLocks[serverId] ?? Future<void>.value();
    final completer = Completer<T>();
    late final Future<void> tail;
    tail = previous.catchError((_) {}).then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    _serverLocks[serverId] = tail;
    tail.whenComplete(() {
      if (identical(_serverLocks[serverId], tail)) {
        _serverLocks.remove(serverId);
      }
    });
    return completer.future;
  }

  List<CronTask> list(int serverId) => _repository.list(serverId);
  List<CronExecutionHistory> listHistory(
    int taskId, {
    int limit = 100,
    int offset = 0,
  }) => _repository.listHistory(taskId, limit: limit, offset: offset);

  Future<CronTask> create(SshSession session, CronTask task) {
    final serverId = task.serverId;
    if (serverId == null) throw ArgumentError('缺少 serverId。');
    return _serialized(serverId, () async {
      final created = _repository.add(task, connectionId: session.connectionId);
      try {
        await _syncRemoteCrontab(session, serverId);
        return created;
      } catch (_) {
        _repository.delete(created.id!);
        rethrow;
      }
    });
  }

  Future<CronTask?> update(SshSession session, int id, CronTask task) {
    final serverId = task.serverId;
    if (serverId == null) throw ArgumentError('缺少 serverId。');
    return _serialized(serverId, () async {
      final existing = _repository.get(id);
      if (existing == null || existing.serverId != serverId) return null;
      final updated = _repository.update(id, task);
      if (updated == null) return null;
      try {
        await _syncRemoteCrontab(session, serverId);
      } catch (_) {
        _repository.restore(existing);
        try {
          await _writeTaskScript(session, existing);
        } catch (_) {
          // Keep the original failure; the next successful sync rewrites scripts.
        }
        rethrow;
      }
      return updated;
    });
  }

  Future<bool> delete(SshSession session, int id, int serverId) {
    return _serialized(serverId, () async {
      final task = _repository.get(id);
      if (task == null || task.serverId != serverId) return false;
      if (!_repository.delete(id)) return false;
      try {
        await _syncRemoteCrontab(session, serverId);
      } catch (_) {
        _repository.restore(task);
        rethrow;
      }
      // The task is already unscheduled; script cleanup is best effort.
      try {
        await _sshRepository.execWithResult(
          session,
          'rm -f $_baseDir/task-$id.sh',
          login: false,
        );
      } catch (_) {}
      return true;
    });
  }

  Future<CronExecutionHistory> runNow(SshSession session, CronTask task) async {
    final serverId = task.serverId;
    if (serverId == null) throw ArgumentError('缺少 serverId。');
    final startedAt = DateTime.now().millisecondsSinceEpoch;
    final result = await _sshRepository.execWithResult(
      session,
      'HOSTDECK_TRIGGER=manual $_baseDir/task-${task.id}.sh',
      timeout: const Duration(minutes: 10),
      login: false,
    );
    final finishedAt = DateTime.now().millisecondsSinceEpoch;
    await syncHistory(session, task);
    final synchronized = _repository.listHistory(task.id!, limit: 1);
    if (synchronized.isNotEmpty && synchronized.first.triggerType == 'manual') {
      return synchronized.first;
    }

    final entry = CronExecutionHistory(
      taskId: task.id!,
      serverId: serverId,
      connectionId: session.connectionId,
      triggerType: 'manual',
      startedAt: startedAt,
      finishedAt: finishedAt,
      durationMs: result.durationMs,
      exitCode: result.exitCode,
      status: result.exitCode == 0 ? 'success' : 'failed',
      stdout: result.stdout,
      stderr: result.stderr,
    );
    _repository.addHistory(entry);
    return entry;
  }

  Future<int> syncHistory(SshSession session, CronTask task) async {
    final serverId = task.serverId;
    if (serverId == null) throw ArgumentError('缺少 serverId。');
    final result = await _sshRepository.execWithResult(
      session,
      'test -f $_baseDir/logs/task-${task.id}.log && tail -c 262144 $_baseDir/logs/task-${task.id}.log || true',
      login: false,
    );
    var imported = 0;
    for (final entry in _parseHistory(
      task,
      session.connectionId,
      result.stdout,
    )) {
      _repository.addHistory(entry);
      imported++;
    }
    return imported;
  }

  Future<void> _syncRemoteCrontab(SshSession session, int serverId) async {
    final preserved = _removeManagedEntries(await _readCrontab(session));
    final tasks = _repository.list(serverId);
    for (final task in tasks) {
      await _writeTaskScript(session, task);
    }
    final entries = <String>[...preserved];
    for (final task in tasks) {
      entries.add('# HOSTDECK-CRON:${task.id}:${task.name}');
      final line = '${task.schedule} $_baseDir/task-${task.id}.sh';
      entries.add(task.enabled ? line : '# $line');
    }
    final content = '${entries.join('\n').trimRight()}\n';
    final write = await _sshRepository.execWithResult(
      session,
      'crontab -',
      stdin: content,
      login: false,
    );
    if (write.exitCode != 0) {
      throw StateError(
        write.stderr.isNotEmpty ? write.stderr : '无法更新远端 crontab。',
      );
    }
  }

  /// Reads the user's crontab. A missing crontab is an empty one; any other
  /// failure aborts, because writing back would otherwise erase user entries.
  Future<String> _readCrontab(SshSession session) async {
    final result = await _sshRepository.execWithResult(
      session,
      'crontab -l',
      login: false,
    );
    if (result.exitCode == 0) return result.stdout;
    if (result.exitCode != null &&
        RegExp(
          r'no crontab for|no such file or directory',
          caseSensitive: false,
        ).hasMatch(result.stderr)) {
      return '';
    }
    final detail = result.stderr.trim();
    throw StateError(
      detail.isEmpty
          ? '无法读取远端 crontab，已中止以避免覆盖现有任务。'
          : '无法读取远端 crontab：$detail',
    );
  }

  Future<void> _writeTaskScript(SshSession session, CronTask task) async {
    final id = task.id!;
    final script =
        '''#!/bin/sh
BASE="$_baseDir"
LOG_DIR="\$BASE/logs"
mkdir -p "\$LOG_DIR"
LOG="\$LOG_DIR/task-$id.log"
OUT="\$LOG_DIR/.task-$id.\$\$.out"
ERR="\$LOG_DIR/.task-$id.\$\$.err"
STARTED=\$(date +%s)
TRIGGER=\${HOSTDECK_TRIGGER:-scheduled}
printf 'BEGIN\\t%s\\t%s\\n' "\$STARTED" "\$TRIGGER" >> "\$LOG"
# Prefer a login shell for the user's PATH, but fall back when the profile is
# broken (e.g. it sources bash-only files) and cannot even start a shell.
if sh -lc : >/dev/null 2>&1; then SHELL_FLAGS=-lc; else SHELL_FLAGS=-c; fi
sh "\$SHELL_FLAGS" ${_shellQuote(task.command)} > "\$OUT" 2> "\$ERR"
STATUS=\$?
sed 's/^/OUT\\t/' "\$OUT" >> "\$LOG"
sed 's/^/ERR\\t/' "\$ERR" >> "\$LOG"
FINISHED=\$(date +%s)
printf 'END\\t%s\\t%s\\n' "\$FINISHED" "\$STATUS" >> "\$LOG"
rm -f "\$OUT" "\$ERR"
exit "\$STATUS"
''';
    final path = '$_baseDir/task-$id.sh';
    final mkdir = await _sshRepository.execWithResult(
      session,
      'mkdir -p $_baseDir/logs',
      login: false,
    );
    if (mkdir.exitCode != 0) throw StateError(mkdir.stderr);
    final write = await _sshRepository.execWithResult(
      session,
      'cat > $path',
      stdin: script,
      login: false,
    );
    if (write.exitCode != 0) throw StateError(write.stderr);
    final chmod = await _sshRepository.execWithResult(
      session,
      'chmod 700 $path',
      login: false,
    );
    if (chmod.exitCode != 0) throw StateError(chmod.stderr);
  }

  List<String> _removeManagedEntries(String content) {
    final lines = content.replaceAll('\r\n', '\n').split('\n');
    final retained = <String>[];
    var skipNext = false;
    for (final line in lines) {
      if (skipNext) {
        skipNext = false;
        continue;
      }
      if (line.startsWith('# HOSTDECK-CRON:')) {
        skipNext = true;
        continue;
      }
      retained.add(line);
    }
    while (retained.isNotEmpty && retained.last.isEmpty) {
      retained.removeLast();
    }
    return retained;
  }

  List<CronExecutionHistory> _parseHistory(
    CronTask task,
    String connectionId,
    String content,
  ) {
    final entries = <CronExecutionHistory>[];
    _PendingHistory? pending;
    for (final line in content.split('\n')) {
      final parts = line.split('\t');
      if (parts.length >= 3 && parts[0] == 'BEGIN') {
        final seconds = int.tryParse(parts[1]);
        pending = seconds == null
            ? null
            : _PendingHistory(seconds * 1000, parts[2]);
      } else if (pending != null && parts.length >= 2 && parts[0] == 'OUT') {
        pending.stdout.add(parts.sublist(1).join('\t'));
      } else if (pending != null && parts.length >= 2 && parts[0] == 'ERR') {
        pending.stderr.add(parts.sublist(1).join('\t'));
      } else if (pending != null && parts.length >= 3 && parts[0] == 'END') {
        final finishedSeconds = int.tryParse(parts[1]);
        final exitCode = int.tryParse(parts[2]);
        if (finishedSeconds != null && exitCode != null) {
          final finishedAt = finishedSeconds * 1000;
          entries.add(
            CronExecutionHistory(
              taskId: task.id!,
              serverId: task.serverId,
              connectionId: connectionId,
              triggerType: pending.triggerType,
              startedAt: pending.startedAt,
              finishedAt: finishedAt,
              durationMs: finishedAt - pending.startedAt,
              exitCode: exitCode,
              status: exitCode == 0 ? 'success' : 'failed',
              stdout: pending.stdout.join('\n'),
              stderr: pending.stderr.join('\n'),
            ),
          );
        }
        pending = null;
      }
    }
    return entries;
  }

  String _shellQuote(String value) => "'${value.replaceAll("'", "'\\''")}'";
}

class _PendingHistory {
  final int startedAt;
  final String triggerType;
  final List<String> stdout = [];
  final List<String> stderr = [];
  _PendingHistory(this.startedAt, this.triggerType);
}
