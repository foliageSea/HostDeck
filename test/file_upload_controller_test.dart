import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:test/test.dart';
import 'package:host_deck/server/core/ssh/ssh_service.dart';
import 'package:host_deck/server/core/ssh/ssh_session.dart';
import 'package:host_deck/server/features/files/file_controller.dart';
import 'package:host_deck/server/features/files/file_service.dart';
import 'package:host_deck/server/features/files/file_task_manager.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

void main() {
  test(
    'preserves a permission error and drains the request when open fails',
    () async {
      final failureSeen = Completer<void>();
      var drained = false;
      final files = _Files((_, _) async {
        failureSeen.complete();
        throw SftpStatusError(SftpStatusCode.permissionDenied, 'denied');
      });
      final response = await _controller(files).uploadFile(
        _request(() async* {
          yield _part('archive.zip');
          await failureSeen.future;
          for (var i = 0; i < 4; i++) {
            yield List.filled(65536, 65);
          }
          yield _part('do-not-upload.zip', afterFirst: true);
          yield utf8.encode('ignored');
          drained = true;
          yield _ending;
        }()),
      );
      expect(response.statusCode, 403);
      expect(
        jsonDecode(await response.readAsString())['message'],
        contains('权限不足'),
      );
      expect(drained, isTrue);
      expect(files.paths, ['/media/archive.zip']);
    },
  );

  test(
    'drains a partially consumed part after an SFTP write failure',
    () async {
      final failed = Completer<void>();
      var drained = false;
      final files = _Files((_, body) async {
        expect((await body.first).first, 65);
        failed.complete();
        throw SftpStatusError(SftpStatusCode.failure, 'disk quota exceeded');
      });
      final response = await _controller(files).uploadFile(
        _request(() async* {
          yield [..._part('archive.zip'), ...List.filled(65536, 65)];
          await failed.future;
          yield List.filled(65536, 66);
          drained = true;
          yield _ending;
        }()),
      );
      expect(response.statusCode, 500);
      expect(await response.readAsString(), contains('disk quota exceeded'));
      expect(drained, isTrue);
    },
  );

  test(
    'HTTP client receives JSON 403 while sending a large rejected file',
    () async {
      final files = _Files((_, _) async {
        throw SftpStatusError(SftpStatusCode.permissionDenied, 'denied');
      });
      final server = await shelf_io.serve(
        _controller(files).uploadFile,
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() => server.close(force: true));
      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final header = _part('large.zip');
      final chunk = List<int>.filled(65536, 65);
      final total = header.length + chunk.length * 128 + _ending.length;
      final request = await client.postUrl(
        Uri.parse(
          'http://127.0.0.1:${server.port}/api/files/upload?connectionId=test&path=%2Fmedia',
        ),
      );
      request.headers.set(
        HttpHeaders.contentTypeHeader,
        'multipart/form-data; boundary=upload-boundary',
      );
      request.contentLength = total;
      await request.addStream(() async* {
        yield header;
        for (var i = 0; i < 128; i++) {
          yield chunk;
        }
        yield _ending;
      }());
      final response = await request.close();
      expect(response.statusCode, 403);
      expect(
        jsonDecode(await utf8.decoder.bind(response).join())['message'],
        contains('权限不足'),
      );
    },
  );

  test('streams valid files after discarding ordinary form fields', () async {
    final received = <int>[];
    final files = _Files((_, body) => body.forEach(received.addAll));
    final response = await _controller(files).uploadFile(
      _request(
        Stream.fromIterable([
          utf8.encode(
            '--upload-boundary\r\nContent-Disposition: form-data; name="meta"\r\n\r\nignored',
          ),
          _part('archive.zip', afterFirst: true),
          [0, 1, 255, 2],
          _ending,
        ]),
      ),
    );
    expect(response.statusCode, 200);
    expect(received, [0, 1, 255, 2]);
    expect(files.paths, ['/media/archive.zip']);
  });
}

Request _request(Stream<List<int>> body) => Request(
  'POST',
  Uri.parse(
    'http://localhost/api/files/upload?connectionId=test&path=%2Fmedia',
  ),
  headers: {'content-type': 'multipart/form-data; boundary=upload-boundary'},
  body: body,
);

List<int> _part(String filename, {bool afterFirst = false}) => utf8.encode(
  '${afterFirst ? '\r\n' : ''}--upload-boundary\r\nContent-Disposition: form-data; name="file"; filename="$filename"\r\n\r\n',
);
final _ending = utf8.encode('\r\n--upload-boundary--\r\n');

FileController _controller(_Files files) =>
    FileController(_Ssh(), files, _Tasks());

class _Files implements FileService {
  final Future<void> Function(String, Stream<List<int>>) write;
  final paths = <String>[];
  _Files(this.write);

  @override
  Future<void> writeFileStream(
    SshSession session,
    String path,
    Stream<List<int>> content,
  ) {
    paths.add(path);
    return write(path, content);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Ssh extends SshService {
  @override
  Future<SshSession> createSftpSession(
    String connectionId, {
    required SshSessionPurpose purpose,
  }) async =>
      SshSession(id: 'sftp', connectionId: connectionId, client: _Client());
}

class _Client implements SSHClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Tasks implements FileTaskManager {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
