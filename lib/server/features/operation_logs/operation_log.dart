class OperationLog {
  final int? id;
  final String category;
  final String action;
  final String? target;
  final Map<String, dynamic>? detail;
  final String status;
  final String? errorMessage;
  final String? connectionId;
  final int createdAt;

  OperationLog({
    this.id,
    required this.category,
    required this.action,
    this.target,
    this.detail,
    required this.status,
    this.errorMessage,
    this.connectionId,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'category': category,
    'action': action,
    'target': target,
    'detail': detail,
    'status': status,
    'errorMessage': errorMessage,
    'connectionId': connectionId,
    'createdAt': createdAt,
  };
}
