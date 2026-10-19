class CronTask {
  final int? id;
  final int? serverId;
  final String? connectionId;
  final String name;
  final String schedule;
  final String command;
  final bool enabled;
  final String? templateType;
  final int? createdAt;
  final int? updatedAt;

  const CronTask({
    this.id,
    this.serverId,
    this.connectionId,
    required this.name,
    required this.schedule,
    required this.command,
    required this.enabled,
    this.templateType,
    this.createdAt,
    this.updatedAt,
  });

  factory CronTask.fromJson(Map<String, dynamic> json) {
    final serverId = _asInt(json['serverId']);
    final name = (json['name'] ?? '').toString().trim();
    final schedule = (json['schedule'] ?? '').toString().trim();
    final command = (json['command'] ?? '').toString().trim();
    final templateType = (json['templateType'] ?? '').toString().trim();

    if (serverId == null) throw ArgumentError('缺少 serverId。');
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
      serverId: serverId,
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
    'serverId': serverId,
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
    final fields = value.split(RegExp(r'\s+'));
    if (fields.length != 5) return false;
    return _isValidField(fields[0], 0, 59) &&
        _isValidField(fields[1], 0, 23) &&
        _isValidField(fields[2], 1, 31) &&
        _isValidField(fields[3], 1, 12, names: _monthNames) &&
        _isValidField(fields[4], 0, 7, names: _weekdayNames);
  }

  static const _monthNames = {
    'jan': 1,
    'feb': 2,
    'mar': 3,
    'apr': 4,
    'may': 5,
    'jun': 6,
    'jul': 7,
    'aug': 8,
    'sep': 9,
    'oct': 10,
    'nov': 11,
    'dec': 12,
  };
  static const _weekdayNames = {
    'sun': 0,
    'mon': 1,
    'tue': 2,
    'wed': 3,
    'thu': 4,
    'fri': 5,
    'sat': 6,
  };

  /// Validates one cron field: comma lists of `*`, values or ranges with an
  /// optional `/step`.
  static bool _isValidField(
    String field,
    int min,
    int max, {
    Map<String, int> names = const {},
  }) {
    if (field.isEmpty) return false;
    int? parse(String token) {
      final named = names[token.toLowerCase()];
      if (named != null) return named;
      if (!RegExp(r'^\d{1,2}$').hasMatch(token)) return null;
      return int.parse(token);
    }

    for (final item in field.split(',')) {
      final stepParts = item.split('/');
      if (stepParts.length > 2) return false;
      if (stepParts.length == 2) {
        final step = int.tryParse(stepParts[1]);
        if (!RegExp(r'^\d{1,3}$').hasMatch(stepParts[1]) ||
            step == null ||
            step < 1) {
          return false;
        }
      }
      final range = stepParts[0];
      if (range == '*') continue;
      final bounds = range.split('-');
      if (bounds.length > 2) return false;
      final start = parse(bounds[0]);
      final end = bounds.length == 2 ? parse(bounds[1]) : start;
      if (start == null || end == null) return false;
      if (start < min || end > max || start > end) return false;
    }
    return true;
  }

  static bool _hasLineBreak(String value) =>
      value.contains('\n') || value.contains('\r');
  static int? _asInt(Object? value) =>
      value == null ? null : int.tryParse(value.toString());
}

class CronExecutionHistory {
  final int? id;
  final int taskId;
  final int? serverId;
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
    this.serverId,
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
    'serverId': serverId,
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
