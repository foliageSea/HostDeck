import 'package:flutter_test/flutter_test.dart';
import 'package:ssh_tool/server/models/process_info.dart';
import 'package:ssh_tool/server/repositories/ssh_repository.dart';
import 'package:ssh_tool/server/services/process_service.dart';

class _UnusedSshRepository extends SshRepository {}

void main() {
  final service = ProcessService(_UnusedSshRepository());

  test('parseProcessListLine parses linux ps output', () {
    const line =
        '123 1 root 12.5 8.3 Sl Mon May 12 10:11:12 2026 3600 python python app.py --port 8080';

    final process = service.parseProcessListLine(line);

    expect(process.pid, 123);
    expect(process.ppid, 1);
    expect(process.user, 'root');
    expect(process.cpuPercent, 12.5);
    expect(process.memoryPercent, 8.3);
    expect(process.state, 'Sl');
    expect(process.startTime, 'Mon May 12 10:11:12 2026');
    expect(process.elapsed, '3600');
    expect(process.command, 'python');
    expect(process.commandLine, 'python app.py --port 8080');
  });

  test('parseProcessDetail parses single process detail', () {
    const line =
        '321 1 321 321 deploy 0.3 1.4 S Mon May 12 11:22:33 2026 95 ? node node /srv/app/server.js';

    final detail = service.parseProcessDetail(line, 321);

    expect(detail.pid, 321);
    expect(detail.ppid, 1);
    expect(detail.pgid, 321);
    expect(detail.sid, 321);
    expect(detail.user, 'deploy');
    expect(detail.tty, '?');
    expect(detail.command, 'node');
    expect(detail.commandLine, 'node /srv/app/server.js');
  });

  test('buildProcessTree links parent and child nodes', () {
    const processes = [
      ProcessInfo(
        pid: 1,
        ppid: 0,
        user: 'root',
        cpuPercent: 0,
        memoryPercent: 0,
        state: 'S',
        startTime: 'Mon May 12 00:00:00 2026',
        elapsed: '100',
        command: 'init',
        commandLine: 'init',
      ),
      ProcessInfo(
        pid: 10,
        ppid: 1,
        user: 'app',
        cpuPercent: 0,
        memoryPercent: 0,
        state: 'S',
        startTime: 'Mon May 12 00:01:00 2026',
        elapsed: '90',
        command: 'node',
        commandLine: 'node app.js',
      ),
      ProcessInfo(
        pid: 11,
        ppid: 10,
        user: 'app',
        cpuPercent: 0,
        memoryPercent: 0,
        state: 'S',
        startTime: 'Mon May 12 00:01:30 2026',
        elapsed: '80',
        command: 'worker',
        commandLine: 'worker --queue=high',
      ),
    ];

    final tree = service.buildProcessTree(processes);

    expect(tree, hasLength(1));
    expect(tree.first.pid, 1);
    expect(tree.first.children, hasLength(1));
    expect(tree.first.children.first.pid, 10);
    expect(tree.first.children.first.children, hasLength(1));
    expect(tree.first.children.first.children.first.pid, 11);
  });

  test('buildStartCommand quotes cwd and env safely', () {
    final command = service.buildStartCommand(
      command: 'python app.py --config "prod file"',
      workingDirectory: '/srv/my app',
      environment: {'APP_ENV': 'production', 'APP_NAME': 'demo service'},
      logPath: '/tmp/process.log',
    );

    expect(command, contains('/srv/my app'));
    expect(command, contains('APP_ENV='));
    expect(command, contains('production'));
    expect(command, contains('APP_NAME='));
    expect(command, contains('demo service'));
    expect(command, contains('/tmp/process.log'));
    expect(command, contains('nohup sh -lc'));
  });
}
