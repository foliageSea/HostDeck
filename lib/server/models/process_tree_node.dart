import 'process_info.dart';

class ProcessTreeNode extends ProcessInfo {
  final List<ProcessTreeNode> children;

  const ProcessTreeNode({
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
    required this.children,
  });

  factory ProcessTreeNode.fromProcessInfo(
    ProcessInfo process, {
    List<ProcessTreeNode> children = const [],
  }) {
    return ProcessTreeNode(
      pid: process.pid,
      ppid: process.ppid,
      user: process.user,
      cpuPercent: process.cpuPercent,
      memoryPercent: process.memoryPercent,
      state: process.state,
      startTime: process.startTime,
      elapsed: process.elapsed,
      command: process.command,
      commandLine: process.commandLine,
      children: children,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      ...super.toJson(),
      'children': children.map((child) => child.toJson()).toList(),
    };
  }
}
