import '../models/process_info.dart';
import '../models/ssh_session.dart';
import '../repositories/ssh_repository.dart';

class ProcessService {
  final SshRepository _repository;

  ProcessService(this._repository);

  Future<List<ProcessInfo>> listProcesses(SshSession session) async {
    final output = await _repository.exec(session, _processListCommand);
    return output
        .split('\n')
        .map((line) => line.trimRight())
        .where((line) => line.isNotEmpty)
        .map(_parseProcessLine)
        .whereType<ProcessInfo>()
        .toList();
  }

  Future<void> killProcess(SshSession session, int pid) async {
    if (pid <= 0) {
      throw ArgumentError('Invalid pid');
    }

    await _repository.exec(session, 'kill $pid');
  }

  ProcessInfo? _parseProcessLine(String line) {
    final parts = line.split('\t');
    if (parts.length < 9) {
      return null;
    }

    final pid = int.tryParse(parts[0].trim());
    if (pid == null) {
      return null;
    }

    return ProcessInfo(
      pid: pid,
      user: parts[1].trim(),
      cpu: double.tryParse(parts[2].trim()) ?? 0,
      memory: double.tryParse(parts[3].trim()) ?? 0,
      rss: int.tryParse(parts[4].trim()) ?? 0,
      stat: parts[5].trim(),
      start: parts[6].trim(),
      time: parts[7].trim(),
      command: parts.sublist(8).join('\t').trim(),
    );
  }

  static const String _processListCommand = r'''
ps -eo pid=,user=,%cpu=,%mem=,rss=,stat=,start=,time=,args= --sort=-%cpu,-%mem |
awk 'BEGIN { OFS="\t" } {
  pid=$1; user=$2; cpu=$3; mem=$4; rss=$5; stat=$6; start=$7; time=$8;
  command="";
  for (i=9; i<=NF; i++) command = command (i==9 ? "" : " ") $i;
  print pid, user, cpu, mem, rss, stat, start, time, command;
}'
''';
}
