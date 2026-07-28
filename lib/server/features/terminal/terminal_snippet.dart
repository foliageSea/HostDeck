class TerminalSnippet {
  final int? id;
  final String name;
  final String command;
  final int? createdAt;
  final int? updatedAt;

  const TerminalSnippet({
    this.id,
    required this.name,
    required this.command,
    this.createdAt,
    this.updatedAt,
  });

  factory TerminalSnippet.fromJson(Map<String, dynamic> json) {
    final name = (json['name'] ?? '').toString().trim();
    final command = (json['command'] ?? '').toString().trim();
    if (name.isEmpty) {
      throw ArgumentError('片段名称不能为空。');
    }
    if (command.isEmpty) {
      throw ArgumentError('命令不能为空。');
    }

    return TerminalSnippet(
      id: json['id'] == null ? null : int.tryParse(json['id'].toString()),
      name: name,
      command: command,
      createdAt: json['createdAt'] == null
          ? null
          : int.tryParse(json['createdAt'].toString()),
      updatedAt: json['updatedAt'] == null
          ? null
          : int.tryParse(json['updatedAt'].toString()),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'command': command,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
  };
}
