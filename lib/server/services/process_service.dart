import '../models/process_detail.dart';
import '../models/process_info.dart';
import '../models/process_tree_node.dart';
import '../models/ssh_session.dart';
import '../repositories/ssh_repository.dart';

class ProcessStartResult {
  final int pid;
  final String logPath;
  final String startedCommand;

  const ProcessStartResult({
    required this.pid,
    required this.logPath,
    required this.startedCommand,
  });

  Map<String, dynamic> toJson() {
    return {'pid': pid, 'logPath': logPath, 'startedCommand': startedCommand};
  }
}

class ProcessService {
  final SshRepository _repository;

  ProcessService(this._repository);

  Future<List<ProcessInfo>> listProcesses(
    SshSession session, {
    String? keyword,
    String? user,
    String sortBy = 'cpu',
    String sortOrder = 'desc',
    int? limit,
  }) async {
    final output = await _repository.exec(session, _buildListCommand());
    var processes = parseProcessList(output);

    final normalizedKeyword = keyword?.trim().toLowerCase();
    if (normalizedKeyword != null && normalizedKeyword.isNotEmpty) {
      processes = processes.where((process) {
        return process.pid.toString().contains(normalizedKeyword) ||
            process.user.toLowerCase().contains(normalizedKeyword) ||
            process.command.toLowerCase().contains(normalizedKeyword) ||
            process.commandLine.toLowerCase().contains(normalizedKeyword);
      }).toList();
    }

    final normalizedUser = user?.trim().toLowerCase();
    if (normalizedUser != null && normalizedUser.isNotEmpty) {
      processes = processes
          .where((process) => process.user.toLowerCase() == normalizedUser)
          .toList();
    }

    processes.sort((left, right) {
      final factor = sortOrder.toLowerCase() == 'asc' ? 1 : -1;
      switch (sortBy.toLowerCase()) {
        case 'pid':
          return factor * left.pid.compareTo(right.pid);
        case 'memory':
          return factor * left.memoryPercent.compareTo(right.memoryPercent);
        case 'user':
          return factor * left.user.compareTo(right.user);
        case 'command':
          return factor * left.command.compareTo(right.command);
        case 'cpu':
        default:
          return factor * left.cpuPercent.compareTo(right.cpuPercent);
      }
    });

    if (limit != null && limit >= 0 && processes.length > limit) {
      return processes.take(limit).toList();
    }

    return processes;
  }

  Future<ProcessDetail> getProcessDetail(SshSession session, int pid) async {
    final output = await _repository.exec(session, _buildDetailCommand(pid));
    return parseProcessDetail(output, pid);
  }

  Future<ProcessDetail?> getProcessDetailOrNull(
    SshSession session,
    int pid,
  ) async {
    try {
      return await getProcessDetail(session, pid);
    } catch (error) {
      final message = error.toString();
      if (message.contains('Process $pid not found.')) {
        return null;
      }
      rethrow;
    }
  }

  Future<List<ProcessTreeNode>> getProcessTree(
    SshSession session, {
    String? keyword,
    String? user,
  }) async {
    final processes = await listProcesses(
      session,
      keyword: keyword,
      user: user,
      sortBy: 'pid',
      sortOrder: 'asc',
    );

    return buildProcessTree(processes);
  }

  Future<void> sendSignal(SshSession session, int pid, String signal) async {
    final normalizedSignal = signal.trim().toUpperCase();
    if (normalizedSignal.isEmpty) {
      throw ArgumentError('Signal is required.');
    }

    await _ensureProcessExists(session, pid);
    await _repository.exec(session, 'kill -s $normalizedSignal $pid');
  }

  Future<ProcessStartResult> startProcess(
    SshSession session, {
    required String command,
    String? workingDirectory,
    Map<String, String> environment = const {},
  }) async {
    final trimmedCommand = command.trim();
    if (trimmedCommand.isEmpty) {
      throw ArgumentError('Command is required.');
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final logPath = '/tmp/ssh_tool_process_$timestamp.log';

    final output = await _repository.exec(
      session,
      buildStartCommand(
        command: trimmedCommand,
        workingDirectory: workingDirectory,
        environment: environment,
        logPath: logPath,
      ),
    );
    final pid = int.tryParse(output.trim());
    if (pid == null || pid <= 0) {
      throw Exception('Failed to start process: invalid PID returned.');
    }

    return ProcessStartResult(
      pid: pid,
      logPath: logPath,
      startedCommand: trimmedCommand,
    );
  }

  List<ProcessInfo> parseProcessList(String output) {
    final lines = output
        .split('\n')
        .map((line) => line.trimRight())
        .where((line) => line.trim().isNotEmpty)
        .toList();

    return lines.map(parseProcessListLine).toList();
  }

  ProcessInfo parseProcessListLine(String line) {
    final parts = line.trim().split(RegExp(r'\s+'));
    if (parts.length < 14) {
      throw FormatException('Invalid process list line: $line');
    }

    final args = parts.length > 13 ? parts.sublist(13).join(' ').trim() : '';
    final commandLine = args.isNotEmpty ? args : parts[12].trim();

    return ProcessInfo(
      pid: _parseInt(parts[0], 'pid'),
      ppid: _parseInt(parts[1], 'ppid'),
      user: parts[2].trim(),
      cpuPercent: _parseDouble(parts[3]),
      memoryPercent: _parseDouble(parts[4]),
      state: parts[5].trim(),
      startTime: parts.sublist(6, 11).join(' '),
      elapsed: parts[11].trim(),
      command: parts[12].trim(),
      commandLine: commandLine,
    );
  }

  ProcessDetail parseProcessDetail(String output, int pid) {
    final lines = output
        .split('\n')
        .map((line) => line.trimRight())
        .where((line) => line.trim().isNotEmpty)
        .toList();
    if (lines.isEmpty) {
      throw Exception('Process $pid not found.');
    }

    final parts = lines.first.trim().split(RegExp(r'\s+'));
    if (parts.length < 17) {
      throw FormatException('Invalid process detail line: ${lines.first}');
    }

    final args = parts.length > 16 ? parts.sublist(16).join(' ').trim() : '';
    final commandLine = args.isNotEmpty ? args : parts[15].trim();

    return ProcessDetail(
      pid: _parseInt(parts[0], 'pid'),
      ppid: _parseInt(parts[1], 'ppid'),
      pgid: _parseInt(parts[2], 'pgid'),
      sid: _parseInt(parts[3], 'sid'),
      user: parts[4].trim(),
      cpuPercent: _parseDouble(parts[5]),
      memoryPercent: _parseDouble(parts[6]),
      state: parts[7].trim(),
      startTime: parts.sublist(8, 13).join(' '),
      elapsed: parts[13].trim(),
      tty: parts[14].trim(),
      command: parts[15].trim(),
      commandLine: commandLine,
    );
  }

  List<ProcessTreeNode> buildProcessTree(List<ProcessInfo> processes) {
    final childrenByParent = <int, List<ProcessInfo>>{};
    final processByPid = <int, ProcessInfo>{};

    for (final process in processes) {
      processByPid[process.pid] = process;
      childrenByParent.putIfAbsent(process.ppid, () => []).add(process);
    }

    ProcessTreeNode buildNode(ProcessInfo process) {
      final children = (childrenByParent[process.pid] ?? [])
        ..sort((left, right) => left.pid.compareTo(right.pid));

      return ProcessTreeNode.fromProcessInfo(
        process,
        children: children.map(buildNode).toList(),
      );
    }

    final roots =
        processes
            .where((process) => !processByPid.containsKey(process.ppid))
            .toList()
          ..sort((left, right) => left.pid.compareTo(right.pid));

    return roots.map(buildNode).toList();
  }

  String buildStartCommand({
    required String command,
    String? workingDirectory,
    Map<String, String> environment = const {},
    required String logPath,
  }) {
    final trimmedCommand = command.trim();
    if (trimmedCommand.isEmpty) {
      throw ArgumentError('Command is required.');
    }

    final commandParts = <String>[];
    final trimmedDirectory = workingDirectory?.trim();
    if (trimmedDirectory != null && trimmedDirectory.isNotEmpty) {
      commandParts.add('cd ${_shellQuote(trimmedDirectory)}');
    }

    if (environment.isNotEmpty) {
      final exports = environment.entries
          .where(
            (entry) =>
                entry.key.trim().isNotEmpty && entry.value.trim().isNotEmpty,
          )
          .map(
            (entry) =>
                '${_escapeEnvKey(entry.key.trim())}=${_shellQuote(entry.value.trim())}',
          )
          .join(' ');
      if (exports.isNotEmpty) {
        commandParts.add('export $exports');
      }
    }

    commandParts.add(
      'nohup sh -lc ${_shellQuote(trimmedCommand)} > ${_shellQuote(logPath)} 2>&1 & echo \$!',
    );

    return 'sh -lc ${_shellQuote(commandParts.join(' && '))}';
  }

  String _buildListCommand() {
    return 'ps -eo pid=,ppid=,user=,%cpu=,%mem=,stat=,lstart=,etimes=,comm=,args= --no-headers';
  }

  String _buildDetailCommand(int pid) {
    return 'ps -p $pid -o pid=,ppid=,pgid=,sid=,user=,%cpu=,%mem=,stat=,lstart=,etimes=,tty=,comm=,args= --no-headers';
  }

  Future<void> _ensureProcessExists(SshSession session, int pid) async {
    final output = await _repository.exec(
      session,
      'ps -p $pid -o pid= --no-headers',
    );
    if (output.trim().isEmpty) {
      throw Exception('Process $pid not found.');
    }
  }

  int _parseInt(String value, String fieldName) {
    final result = int.tryParse(value.trim());
    if (result == null) {
      throw FormatException('Invalid $fieldName: $value');
    }

    return result;
  }

  double _parseDouble(String value) {
    return double.tryParse(value.trim().replaceAll(',', '.')) ?? 0.0;
  }

  String _shellQuote(String value) {
    return "'${value.replaceAll("'", "'\\''")}'";
  }

  String _escapeEnvKey(String value) {
    final normalized = value.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_');
    if (normalized.isEmpty || RegExp(r'^[0-9]').hasMatch(normalized)) {
      throw ArgumentError('Invalid environment variable name: $value');
    }
    return normalized;
  }
}
