enum FileTaskType { copy, move, delete, extract, compress }

enum FileTaskStatus { queued, running, success, failed, cancelled }

class FileTaskItem {
  final int id;
  final String sourcePath;
  final String? targetPath;
  final FileTaskStatus status;
  final String? errorMessage;
  final int? startedAt;
  final int? finishedAt;

  const FileTaskItem({
    required this.id,
    required this.sourcePath,
    required this.targetPath,
    required this.status,
    required this.errorMessage,
    required this.startedAt,
    required this.finishedAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'sourcePath': sourcePath,
    'targetPath': targetPath,
    'status': status.name,
    'errorMessage': errorMessage,
    'startedAt': startedAt,
    'finishedAt': finishedAt,
  };
}

class FileTask {
  final String id;
  final String connectionId;
  final FileTaskType type;
  final FileTaskStatus status;
  final String? errorMessage;
  final int createdAt;
  final int? startedAt;
  final int? finishedAt;
  final List<FileTaskItem> items;

  const FileTask({
    required this.id,
    required this.connectionId,
    required this.type,
    required this.status,
    required this.errorMessage,
    required this.createdAt,
    required this.startedAt,
    required this.finishedAt,
    required this.items,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'connectionId': connectionId,
    'type': type.name,
    'status': status.name,
    'errorMessage': errorMessage,
    'createdAt': createdAt,
    'startedAt': startedAt,
    'finishedAt': finishedAt,
    'items': items.map((item) => item.toJson()).toList(),
  };
}
