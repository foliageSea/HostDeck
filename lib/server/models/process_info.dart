class ProcessInfo {
  final int pid;
  final int ppid;
  final String user;
  final double cpuPercent;
  final double memoryPercent;
  final String state;
  final String startTime;
  final String elapsed;
  final String command;
  final String commandLine;

  const ProcessInfo({
    required this.pid,
    required this.ppid,
    required this.user,
    required this.cpuPercent,
    required this.memoryPercent,
    required this.state,
    required this.startTime,
    required this.elapsed,
    required this.command,
    required this.commandLine,
  });

  Map<String, dynamic> toJson() {
    return {
      'pid': pid,
      'ppid': ppid,
      'user': user,
      'cpuPercent': cpuPercent,
      'memoryPercent': memoryPercent,
      'state': state,
      'startTime': startTime,
      'elapsed': elapsed,
      'command': command,
      'commandLine': commandLine,
    };
  }
}
