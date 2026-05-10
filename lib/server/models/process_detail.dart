import 'process_info.dart';

class ProcessDetail extends ProcessInfo {
  final int pgid;
  final int sid;
  final String tty;

  const ProcessDetail({
    required super.pid,
    required super.ppid,
    required super.user,
    required super.cpuPercent,
    required super.memoryPercent,
    required super.state,
    required super.startTime,
    required super.elapsed,
    required super.command,
    required super.commandLine,
    required this.pgid,
    required this.sid,
    required this.tty,
  });

  @override
  Map<String, dynamic> toJson() {
    return {...super.toJson(), 'pgid': pgid, 'sid': sid, 'tty': tty};
  }
}
