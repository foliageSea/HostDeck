import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:host_deck/server/core/ssh/ssh_operation_limiter.dart';
import 'package:host_deck/server/core/ssh/ssh_repository.dart';
import 'package:host_deck/server/core/ssh/ssh_session.dart';

void main() {
  test(
    'a stalled SFTP upload times out and closes only its SFTP channel',
    () async {
      final writer = _UploadWriter();
      final file = _UploadFile(writer);
      final sftp = _UploadSftp(file);
      final session = _UploadSession(sftp);

      await expectLater(
        SshRepository().writeFileStream(
          session,
          '/archive.tar.gz',
          const Stream.empty(),
          idleTimeout: const Duration(milliseconds: 20),
        ),
        throwsA(isA<TimeoutException>()),
      );

      expect(sftp.closed, isTrue);
      expect(writer.aborted, isTrue);
    },
  );

  test(
    'SFTP progress uses remote acknowledgements and closes the file',
    () async {
      final writer = _UploadWriter();
      final file = _UploadFile(writer);
      final sftp = _UploadSftp(file);
      final progress = <int>[];
      final upload = SshRepository().writeFileStream(
        _UploadSession(sftp),
        '/archive.tar.gz',
        const Stream.empty(),
        onProgress: progress.add,
        idleTimeout: const Duration(seconds: 1),
      );
      await file.started.future;
      expect(progress, isEmpty);
      file.onProgress!(16384);
      writer.completion.complete();
      await upload;

      expect(progress, [16384]);
      expect(file.closed, isTrue);
      expect(sftp.closed, isFalse);
      expect(writer.aborted, isFalse);
    },
  );

  for (final operation
      in <String, Future<void> Function(SshRepository, SshSession)>{
        'copy': (repository, session) =>
            repository.copy(session, '/source', '/target'),
        'delete': (repository, session) =>
            repository.delete(session, '/target'),
      }.entries) {
    test('${operation.key} reports a non-zero remote exit code', () async {
      final session = _FakeSshSession(
        _FakeSshClient(
          SSHRunResult(
            output: Uint8List.fromList('permission denied'.codeUnits),
            stdout: Uint8List(0),
            stderr: Uint8List.fromList('permission denied'.codeUnits),
            exitCode: 1,
            exitSignal: null,
          ),
        ),
      );

      await expectLater(
        operation.value(SshRepository(), session),
        throwsA(
          isA<Exception>().having(
            (error) => error.toString(),
            'message',
            contains('permission denied'),
          ),
        ),
      );
    });
  }

  test('cancelling an exec sends TERM and closes its SSH channel', () async {
    final process = _CancellableSshProcess();
    final client = _ExecutingSshClient(process);
    final session = _FakeSshSession(client);
    final cancellation = Completer<void>();
    final execution = SshRepository().execWithResult(
      session,
      'sleep 600',
      login: false,
      cancellation: cancellation.future,
    );
    await client.executed.future;

    cancellation.complete();

    await expectLater(execution, throwsA(isA<SshExecCancelledException>()));
    expect(process.signal, SSHSignal.TERM);
    expect(process.closed, isTrue);
  });

  test('an already cancelled exec never starts a remote process', () async {
    final process = _CancellableSshProcess();
    final client = _ExecutingSshClient(process);
    final session = _FakeSshSession(client);

    await expectLater(
      SshRepository().execWithResult(
        session,
        'touch /tmp/should-not-run',
        login: false,
        cancellation: Future.value(),
        isCancelled: () => true,
      ),
      throwsA(isA<SshExecCancelledException>()),
    );
    expect(client.executed.isCompleted, isFalse);
  });
}

class _UploadWriter implements SftpFileWriter {
  final completion = Completer<void>();
  bool aborted = false;

  @override
  Future<void> get done => completion.future;

  @override
  Future<void> abort() async {
    aborted = true;
    if (!completion.isCompleted) completion.complete();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UploadFile implements SftpFile {
  final _UploadWriter writer;
  final started = Completer<void>();
  void Function(int)? onProgress;
  bool closed = false;

  _UploadFile(this.writer);

  @override
  SftpFileWriter write(
    Stream<Uint8List> stream, {
    int offset = 0,
    void Function(int)? onProgress,
    int chunkSize = 16384,
    int maxPendingRequests = 64,
  }) {
    this.onProgress = onProgress;
    started.complete();
    return writer;
  }

  @override
  Future<void> close() async => closed = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UploadSftp implements SftpClient {
  final _UploadFile file;
  bool closed = false;

  _UploadSftp(this.file);

  @override
  Future<SftpFile> open(
    String path, {
    SftpFileOpenMode mode = SftpFileOpenMode.read,
  }) async => file;

  @override
  Future<void> close() async => closed = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UploadSession extends _FakeSshSession {
  final _UploadSftp channel;

  _UploadSession(this.channel)
    : super(_ExecutingSshClient(_CancellableSshProcess()));

  @override
  Future<SftpClient> sftp() async => channel;
}

class _FakeSshClient implements SSHClient {
  final SSHRunResult result;

  _FakeSshClient(this.result);

  @override
  Future<SSHRunResult> runWithResult(
    String command, {
    bool runInPty = false,
    bool stdout = true,
    bool stderr = true,
    Map<String, String>? environment,
  }) async => result;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ExecutingSshClient implements SSHClient {
  final SSHSession process;
  final Completer<void> executed = Completer<void>();

  _ExecutingSshClient(this.process);

  @override
  Future<SSHSession> execute(
    String command, {
    SSHPtyConfig? pty,
    SSHX11Config? x11,
    Map<String, String>? environment,
  }) async {
    executed.complete();
    return process;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CancellableSshProcess implements SSHSession {
  final _stdin = StreamController<Uint8List>.broadcast();
  final _stdout = StreamController<Uint8List>();
  final _stderr = StreamController<Uint8List>();
  final _done = Completer<void>();
  SSHSignal? signal;
  bool closed = false;

  @override
  StreamSink<Uint8List> get stdin => _stdin.sink;
  @override
  Stream<Uint8List> get stdout => _stdout.stream;
  @override
  Stream<Uint8List> get stderr => _stderr.stream;
  @override
  Future<void> get done => _done.future;
  @override
  int? get exitCode => null;

  @override
  void kill(SSHSignal value) => signal = value;

  @override
  void close() {
    if (closed) return;
    closed = true;
    unawaited(_stdout.close());
    unawaited(_stderr.close());
    _done.complete();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSshSession implements SshSession {
  @override
  final SSHClient client;
  @override
  final SshOperationLimiter operationLimiter = SshOperationLimiter(
    maxConcurrentOperations: 1,
  );

  _FakeSshSession(this.client);

  @override
  String get id => 'session-1';
  @override
  String get connectionId => 'connection-1';
  @override
  SSHSession? get shell => null;
  @override
  Stream<String> get output => const Stream.empty();
  @override
  StreamController<String> get outputController => StreamController.broadcast();
  @override
  Future<SshOperationPermit> acquireOperation() => operationLimiter.acquire();
  @override
  Future<T> runOperation<T>(FutureOr<T> Function() action) =>
      operationLimiter.run(action);
  @override
  Future<SftpClient> sftp() => throw UnimplementedError();
  @override
  Future<void> close() async {}
}
