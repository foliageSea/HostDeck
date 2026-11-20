part of 'file_sidecar_executor.dart';

class _SidecarTiming {
  final Duration start;
  final Duration ping;
  final Duration heartbeat;
  final Duration operation;
  final Duration cancelGrace;
  final Duration terminationGrace;

  const _SidecarTiming({
    required this.start,
    required this.ping,
    required this.heartbeat,
    required this.operation,
    required this.cancelGrace,
    required this.terminationGrace,
  });
}

class _SidecarTransport {
  final String id;
  final _SidecarTiming timing;
  final void Function(SidecarProgress) onProgress;
  final _outcome = Completer<FileSidecarResult>();
  bool _started = false;
  bool _cancelSent = false;
  bool _termSent = false;
  bool _terminalVerified = false;
  ({String status, String? message, String? code})? _terminal;
  Timer? _watchdog;
  Timer? _pings;
  Timer? _lifetime;
  Timer? _cancelDeadline;

  _SidecarTransport({
    required this.id,
    required this.timing,
    required this.onProgress,
  });

  Future<FileSidecarResult?> run(
    SshSession session, {
    required String command,
    required Uint8List request,
    required Future<void> cancellation,
    required bool Function() isCancelled,
  }) async {
    final cancelled = const FileSidecarResult(cancelled: true);
    var cancelRequested = isCancelled();
    var abandoned = false;
    var sent = false;
    SSHSession? process;
    SSHSession? opened;
    final openingCancelled = Completer<SSHSession?>();
    void onCancel() {
      if (abandoned) return;
      cancelRequested = true;
      if (!sent) {
        if (!openingCancelled.isCompleted) openingCancelled.complete();
      } else if (!_outcome.isCompleted && _terminal == null) {
        _cancel(process!);
      }
    }

    if (cancelRequested) return cancelled;
    unawaited(
      cancellation.then(
        (_) => onCancel(),
        onError: (Object error, StackTrace stack) {
          // A cancellation token is a notification, not the operation outcome.
          onCancel();
        },
      ),
    );

    final permitFuture = session.acquireOperation();
    // A queued permit/channel may complete after cancellation or timeout. Do
    // not let it trigger a run, or pin a limiter slot until the SSH link dies.
    final permit = await Future.any([
      permitFuture,
      openingCancelled.future.then((_) => null),
    ]).timeout(timing.start, onTimeout: () => null);
    if (permit == null) {
      abandoned = true;
      permitFuture.then((permit) => permit.release()).ignore();
      if (cancelRequested || isCancelled()) return cancelled;
      throw const FileSidecarException('start_timeout', '等待 SideCar SSH 通道超时。');
    }

    StreamSubscription<Map<String, dynamic>>? frames;
    StreamSubscription<Uint8List>? stderr;
    try {
      if (cancelRequested || isCancelled()) return cancelled;
      final opening = session.client.execute(command).then((channel) {
        if (abandoned) {
          _closeChannel(channel, force: true);
          return null;
        }
        return opened = channel;
      });
      try {
        process = await Future.any([opening, openingCancelled.future]).timeout(
          timing.start,
          onTimeout: () {
            throw const FileSidecarException(
              'start_timeout',
              'SideCar SSH 通道启动超时。',
            );
          },
        );
      } on SSHChannelRequestError {
        if (cancelRequested || isCancelled()) return cancelled;
        // Explicit SSH exec refusal: no request was submitted.
        return null;
      }
      if (cancelRequested || isCancelled()) return cancelled;
      final active = process!;
      if (active.exitCode != null || active.exitSignal != null) {
        throw const FileSidecarException('start_failed', 'SideCar 未能启动。');
      }

      final stdoutDone = Completer<void>();
      final stderrDone = Completer<void>();
      unawaited(
        Future.wait([
          stdoutDone.future,
          stderrDone.future,
          active.done,
        ]).then((_) => _verifyExit(active.exitCode), onError: _fail),
      );

      frames = decodeSidecarFrames(active.stdout).listen(
        (frame) {
          if (_outcome.isCompleted) return;
          try {
            _receive(frame);
            if (_terminal != null) {
              // Half-close only stdin; OpenSSH can now finish the channel and
              // deliver the exit status while both output streams still drain.
              active.stdin.close().ignore();
            }
          } catch (error, stack) {
            _fail(error, stack);
          }
        },
        onError: (Object error, StackTrace stack) {
          _fail(
            const FileSidecarException('protocol_error', 'SideCar 响应帧无效。'),
            stack,
          );
        },
        onDone: () {
          if (_terminal == null && !_outcome.isCompleted) {
            _fail(
              const FileSidecarException(
                'connection_lost',
                'SideCar 已断开，未收到操作结果。',
              ),
            );
          }
          stdoutDone.complete();
        },
      );
      // Keep the SSH receive window flowing; do not accumulate remote stderr.
      stderr = active.stderr.listen(
        (_) {},
        onError: _fail,
        onDone: stderrDone.complete,
      );

      _armWatchdog(timing.start);
      _lifetime = Timer(timing.operation, () {
        _fail(
          const FileSidecarException('operation_timeout', 'SideCar 运行超过时限。'),
        );
      });
      _pings = Timer.periodic(timing.ping, (_) {
        if (_outcome.isCompleted || _cancelSent || _terminal != null) return;
        try {
          // The channel continuously drains stdin. Flushing here binds the
          // shared TCP IOSink; a concurrent channel write can then fail.
          active.stdin.add(_control('ping'));
        } catch (error, stack) {
          _fail(error, stack);
        }
      });

      // Mark as sent before writing. Neither uncertain delivery nor losing
      // the started acknowledgement permits a replay through legacy code.
      sent = true;
      try {
        active.stdin.add(request);
      } catch (error, stack) {
        _fail(error, stack);
      }
      if (cancelRequested || isCancelled()) onCancel();
      return await _outcome.future;
    } finally {
      abandoned = true;
      _watchdog?.cancel();
      _pings?.cancel();
      _lifetime?.cancel();
      _cancelDeadline?.cancel();
      final active = opened;
      try {
        if (active != null) {
          if (sent && !_terminalVerified) _terminate(active);
          _closeChannel(active, force: !_terminalVerified);
        }
      } finally {
        process = opened = null;
        permit.release();
      }
      if (frames != null) await _bestEffort(frames.cancel);
      if (stderr != null) await _bestEffort(stderr.cancel);
    }
  }

  void _receive(Map<String, dynamic> frame) {
    if (_terminal != null) {
      throw const FileSidecarException('protocol_error', 'SideCar 终止帧后收到额外响应。');
    }
    if (frame['v'] is! int ||
        frame['v'] != sidecarProtocolVersion ||
        frame['id'] != id) {
      throw const FileSidecarException(
        'protocol_error',
        'SideCar 响应协议或任务标识不匹配。',
      );
    }
    if (!_started) {
      if (frame['type'] != 'started') {
        throw const FileSidecarException('protocol_error', 'SideCar 未确认操作已启动。');
      }
      _started = true;
    } else {
      switch (frame['type']) {
        case 'heartbeat':
          break;
        case 'progress':
          final SidecarProgress progress;
          try {
            progress = SidecarProgress.fromJson(frame['progress']);
          } on FormatException {
            throw const FileSidecarException(
              'protocol_error',
              'SideCar 进度帧无效。',
            );
          }
          if (progress.phase == SidecarPhase.deploying ||
              progress.phase == SidecarPhase.legacy) {
            throw const FileSidecarException(
              'protocol_error',
              'SideCar 进度阶段无效。',
            );
          }
          onProgress(progress);
        case 'result':
          _handleResult(frame);
          return;
        default:
          throw const FileSidecarException('protocol_error', 'SideCar 响应类型无效。');
      }
    }
    if (!_cancelSent) _armWatchdog(timing.heartbeat);
  }

  void _handleResult(Map<String, dynamic> frame) {
    final status = frame['status'];
    final message = frame['message'];
    final code = frame['errorCode'];
    if ((status != 'success' && status != 'failed' && status != 'cancelled') ||
        (message != null && message is! String) ||
        (code != null && code is! String)) {
      throw const FileSidecarException('protocol_error', 'SideCar 结果帧无效。');
    }
    _terminal = (
      status: status as String,
      message: message as String?,
      code: code as String?,
    );
    _watchdog?.cancel();
    _lifetime?.cancel();
    _cancelDeadline?.cancel();
    _pings?.cancel();
    _watchdog = Timer(timing.terminationGrace, () {
      _fail(
        const FileSidecarException(
          'exit_unconfirmed',
          'SideCar 未确认退出状态，操作结果未知。',
        ),
      );
    });
  }

  void _verifyExit(int? exitCode) {
    if (_outcome.isCompleted) return;
    final terminal = _terminal;
    final valid = switch (terminal?.status) {
      'success' => exitCode == 0,
      'failed' => exitCode == 1 || exitCode == 2,
      'cancelled' => exitCode == 130,
      _ => false,
    };
    if (!valid || terminal == null) {
      _fail(
        const FileSidecarException(
          'exit_unconfirmed',
          'SideCar 退出状态缺失或与终止帧不一致，操作结果未知。',
        ),
      );
      return;
    }
    _terminalVerified = true;
    switch (terminal.status) {
      case 'success':
        _outcome.complete(const FileSidecarResult(cancelled: false));
      case 'cancelled':
        _outcome.complete(const FileSidecarResult(cancelled: true));
      case 'failed':
        final text = terminal.message;
        _fail(
          FileSidecarException(
            terminal.code ?? 'operation_failed',
            text != null && text.isNotEmpty
                ? String.fromCharCodes(text.runes.take(500))
                : 'SideCar 文件操作失败。',
          ),
        );
    }
  }

  void _armWatchdog(Duration timeout) {
    _watchdog?.cancel();
    _watchdog = Timer(timeout, () {
      _fail(
        _started
            ? const FileSidecarException(
                'heartbeat_timeout',
                'SideCar 心跳超时，操作结果未知。',
              )
            : const FileSidecarException(
                'start_timeout',
                'SideCar 未确认启动，操作结果未知。',
              ),
      );
    });
  }

  Uint8List _control(String type) =>
      encodeSidecarFrame({'v': sidecarProtocolVersion, 'id': id, 'type': type});

  void _cancel(SSHSession process) {
    if (_cancelSent) return;
    _cancelSent = true;
    _watchdog?.cancel();
    _pings?.cancel();
    _lifetime?.cancel();
    try {
      process.stdin.add(_control('cancel'));
    } catch (_) {
      _terminate(process);
    }
    _cancelDeadline = Timer(_termSent ? Duration.zero : timing.cancelGrace, () {
      if (_outcome.isCompleted) return;
      _terminate(process);
      _cancelDeadline = Timer(timing.terminationGrace, () {
        _fail(
          const FileSidecarException(
            'cancel_unconfirmed',
            'SideCar 未确认取消，操作结果未知。',
          ),
        );
      });
    });
  }

  void _terminate(SSHSession process) {
    if (_termSent) return;
    _termSent = true;
    try {
      process.kill(SSHSignal.TERM);
    } catch (_) {
      // The server may not support SSH signals. Closing the channel also
      // delivers EOF, which the worker handles as a cancellation.
    }
  }

  void _closeChannel(SSHSession process, {required bool force}) {
    try {
      process.stdin.close().ignore();
    } catch (_) {
      // The stdin sink may have closed concurrently with the task.
    }
    try {
      process.close();
    } catch (_) {
      // A simultaneous transport disconnect may have closed the channel.
    }
    if (force) {
      try {
        // SSHSession.close asks for EOF. An unresponsive worker can leave
        // the channel half-open, so release that channel after the grace
        // periods without tearing down the shared SSH connection.
        process.channel.destroy();
      } catch (_) {
        // Keep the original task outcome if the peer already disconnected.
      }
    }
  }

  void _fail(Object error, [StackTrace? stack]) {
    if (!_outcome.isCompleted) _outcome.completeError(error, stack);
  }
}
