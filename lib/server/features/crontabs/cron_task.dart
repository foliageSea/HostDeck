class CronTask {
  final int? id;
  final String connectionId;
  final String name;
  final String schedule;
  final String command;
  final bool enabled;
  final String? templateType;
  final int? createdAt;
  final int? updatedAt;

  const CronTask({
    this.id,
    required this.connectionId,
    required this.name,
    required this.schedule,
    required this.command,
    required this.enabled,
    this.templateType,
    this.createdAt,
    this.updatedAt,
  });

  factory CronTask.fromJson(Map<String, dynamic> json) {
    final connectionId = (json['connectionId'] ?? '').toString().trim();
    final name = (json['name'] ?? '').toString().trim();
    final schedule = (json['schedule'] ?? '').toString().trim();
    final command = (json['command'] ?? '').toString().trim();
    final templateType = (json['templateType'] ?? '').toString().trim();

    if (connectionId.isEmpty) throw ArgumentError('缺少 connectionId。');
    if (name.isEmpty) throw ArgumentError('任务名称不能为空。');
    if (name.length > 100 || _hasLineBreak(name)) {
      throw ArgumentError('任务名称不能包含换行且最多 100 个字符。');
    }
    if (!_isValidSchedule(schedule)) throw ArgumentError('Cron 表达式无效。');
    if (command.isEmpty || _hasLineBreak(command)) {
      throw ArgumentError('命令不能为空且不能包含换行。');
    }

    return CronTask(
      id: _asInt(json['id']),
      connectionId: connectionId,
      name: name,
      schedule: schedule,
      command: command,
      enabled: json['enabled'] != false,
      templateType: templateType.isEmpty ? null : templateType,
      createdAt: _asInt(json['createdAt']),
      updatedAt: _asInt(json['updatedAt']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'connectionId': connectionId,
    'name': name,
    'schedule': schedule,
    'command': command,
    'enabled': enabled,
    'templateType': templateType,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
  };

  static bool _isValidSchedule(String value) {
    if (_hasLineBreak(value) || value.isEmpty || value.length > 120) {
      return false;
    }
    if (RegExp(
      r'^@(annually|yearly|monthly|weekly|daily|midnight|hourly|reboot)$',
    ).hasMatch(value)) {
      return true;
    }
    return value.split(RegExp(r'\s+')).length == 5;
  }

  static bool _hasLineBreak(String value) =>
      value.contains('\n') || value.contains('\r');
  static int? _asInt(Object? value) =>
      value == null ? null : int.tryParse(value.toString());
}

class CronExecutionHistory {
  final int? id;
  final int taskId;
  final String connectionId;
  final String triggerType;
  final int startedAt;
  final int? finishedAt;
  final int? durationMs;
  final int? exitCode;
  final String status;
  final String? stdout;
  final String? stderr;

  const CronExecutionHistory({
    this.id,
    required this.taskId,
    required this.connectionId,
    required this.triggerType,
    required this.startedAt,
    this.finishedAt,
    this.durationMs,
    this.exitCode,
    required this.status,
    this.stdout,
    this.stderr,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'taskId': taskId,
    'connectionId': connectionId,
    'triggerType': triggerType,
    'startedAt': startedAt,
    'finishedAt': finishedAt,
    'durationMs': durationMs,
    'exitCode': exitCode,
    'status': status,
    'stdout': stdout,
    'stderr': stderr,
  };
}
