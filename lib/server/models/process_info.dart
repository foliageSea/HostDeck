class ProcessInfo {
  final int pid;
  final String user;
  final double cpu;
  final double memory;
  final int rss;
  final String stat;
  final String start;
  final String time;
  final String command;

  const ProcessInfo({
    required this.pid,
    required this.user,
    required this.cpu,
    required this.memory,
    required this.rss,
    required this.stat,
    required this.start,
    required this.time,
    required this.command,
  });

  Map<String, dynamic> toJson() {
    return {
      'pid': pid,
      'user': user,
      'cpu': cpu,
      'memory': memory,
      'rss': rss,
      'stat': stat,
      'start': start,
      'time': time,
      'command': command,
    };
  }
}
