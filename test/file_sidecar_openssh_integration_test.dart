import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';
import 'package:host_deck/server/core/database/database_service.dart';
import 'package:host_deck/server/core/ssh/ssh_repository.dart';
import 'package:host_deck/server/core/ssh/ssh_service.dart';
import 'package:host_deck/server/features/files/file_sidecar_executor.dart';
import 'package:host_deck/server/features/files/file_controller.dart';
import 'package:host_deck/server/features/files/file_service.dart';
import 'package:host_deck/server/features/files/file_task.dart';
import 'package:host_deck/server/features/files/file_task_manager.dart';
import 'package:host_deck/server/features/files/file_task_repository.dart';
import 'package:host_deck_sidecar/protocol.dart';
import 'package:shelf/shelf.dart';

void main() {
  final env = Platform.environment;
  final port = int.tryParse(env['HOSTDECK_TEST_SIDECAR_SSH_PORT'] ?? '');
  final user = env['HOSTDECK_TEST_SIDECAR_SSH_USER'];
  final keyFile = env['HOSTDECK_TEST_SIDECAR_SSH_KEY'];
  final assetDir = env['HOSTDECK_TEST_SIDECAR_ASSETS'];
  final sharedParents = env['HOSTDECK_TEST_SIDECAR_SHARED_PARENT'] == '1';
  test(
    'real OpenSSH deploys, runs all file tasks, and cancels safely',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'hostdeck-file-sidecar-',
      );
      final database = DatabaseService(dataDir: temp.path);
      final ssh = SshService();
      final repository = SshRepository();
      await database.init();
      final manager = FileTaskManager(
        ssh,
        repository,
        FileTaskRepository(database),
        sidecar: SshFileSidecarExecutor(
          repository,
          sidecarDirectory: assetDir,
          pingInterval: const Duration(milliseconds: 250),
        ),
      );
      addTearDown(() async {
        await manager.dispose();
        ssh.dispose();
        database.close();
        await temp.delete(recursive: true);
      });
      final connectionId = await ssh.connect(
        host: '127.0.0.1',
        port: port!,
        username: user!,
        privateKey: await File(keyFile!).readAsString(),
      );
      final session = await ssh.createSftpSession(
        connectionId,
        purpose: SshSessionPurpose.fileManagement,
      );
      final remoteRoot =
          'sidecar-test-${DateTime.now().microsecondsSinceEpoch}';
      Future<String> command(String shell) async {
        final result = await repository.execWithResult(
          session,
          shell,
          login: false,
        );
        expect(result.exitCode, 0, reason: result.stderr);
        return result.stdout.trim();
      }

      addTearDown(() async {
        try {
          await command('rm -rf -- $remoteRoot');
        } finally {
          await ssh.disconnect(connectionId);
        }
      });
      await command(
        'mkdir -p $remoteRoot/tree/empty && head -c 8388608 /dev/urandom > $remoteRoot/tree/content',
      );

      FileTask create(FileTaskType type, String source, String target) =>
          manager.create(connectionId, type, [
            {
              'sourcePath': '$remoteRoot/$source',
              'targetPath': '$remoteRoot/$target',
            },
          ]);
      Future<List<FileTask>> run(
        FileTaskType type,
        String source,
        String target,
      ) async {
        final task = create(type, source, target);
        final events = await manager
            .watch(task.id)
            .toList()
            .timeout(const Duration(minutes: 2));
        expect(
          events.last.status,
          FileTaskStatus.success,
          reason: events.last.errorMessage,
        );
        expect(
          events.any(
            (task) =>
                task.items.single.progress?.phase == SidecarPhase.deploying,
          ),
          isTrue,
        );
        expect(
          events.any(
            (task) => task.items.single.progress?.phase == SidecarPhase.legacy,
          ),
          isFalse,
        );
        return events;
      }

      final controller = FileController(ssh, FileService(repository), manager);
      final first = create(FileTaskType.copy, 'tree', 'copy');
      final response = controller.streamTask(
        Request('GET', Uri.parse('http://localhost/api/files/tasks/events')),
        first.id,
      );
      expect(response.headers['content-type'], startsWith('text/event-stream'));
      final firstEvents = await response.readAsString().timeout(
        const Duration(minutes: 2),
      );
      expect(firstEvents, startsWith('event: task'));
      expect(firstEvents, contains('event: done'));
      expect(firstEvents, contains('"bytesDone":8388608'));
      expect(firstEvents, isNot(contains('"phase":"legacy"')));
      expect(manager.find(first.id)?.status, FileTaskStatus.success);
      final cachePath = sharedParents
          ? '.hostdeck-file-sidecar'
          : '.local/lib/hostdeck/file-sidecar';
      final locateExecutable = 'find "\$HOME/$cachePath" -type f -perm -u+x';
      final installed = await command(locateExecutable);
      expect(installed.split('\n'), hasLength(1));
      await run(FileTaskType.move, 'copy', 'moved');
      await command('ln -s ../content $remoteRoot/moved/empty/internal-link');
      await run(FileTaskType.compress, 'moved', 'archive.zip');
      await run(FileTaskType.extract, 'archive.zip', 'zip-output');
      await run(FileTaskType.compress, 'moved', 'archive.tar.gz');
      await run(FileTaskType.extract, 'archive.tar.gz', 'tar-output');
      await command(
        'test ! -e $remoteRoot/copy && '
        'test -d $remoteRoot/zip-output/moved/empty && '
        'cmp $remoteRoot/tree/content $remoteRoot/zip-output/moved/content && '
        'cmp $remoteRoot/tree/content $remoteRoot/tar-output/moved/content && '
        'test "\$(readlink $remoteRoot/zip-output/moved/empty/internal-link)" = ../content && '
        'test "\$(readlink $remoteRoot/tar-output/moved/empty/internal-link)" = ../content && '
        'cmp $remoteRoot/tree/content $remoteRoot/tar-output/moved/empty/internal-link',
      );
      expect(await command(locateExecutable), installed);
      if (sharedParents) {
        await command(
          'test "\$(stat -c %a "\$HOME/.local")" = 775 && '
          'test "\$(stat -c %a "\$HOME/$cachePath")" = 700 && '
          'test ! -e "\$HOME/.local/lib/hostdeck/file-sidecar"',
        );
      }

      // Sparse input avoids a second large setup transfer. Cancel after the real
      // work phase rather than relying on deployment timing.
      await command('truncate -s 2G $remoteRoot/large');
      final task = create(FileTaskType.compress, 'large', 'cancelled.zip');
      final stream = manager.watch(task.id);
      final cancelled = Completer<void>();
      final events = await stream
          .map((event) {
            if (!cancelled.isCompleted &&
                event.items.single.progress?.phase == SidecarPhase.working) {
              cancelled.complete();
              unawaited(manager.cancel(task.id));
            }
            return event;
          })
          .toList()
          .timeout(const Duration(minutes: 2));
      expect(cancelled.isCompleted, isTrue);
      expect(
        events.last.status,
        FileTaskStatus.cancelled,
        reason: events.last.errorMessage,
      );
      await command('test ! -e $remoteRoot/cancelled.zip');
    },
    skip: port == null || user == null || keyFile == null || assetDir == null
        ? 'Set HOSTDECK_TEST_SIDECAR_* for a disposable local Linux OpenSSH account.'
        : false,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
