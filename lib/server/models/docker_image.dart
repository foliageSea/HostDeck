class DockerImage {
  final String id;
  final String repository;
  final String tag;
  final String size;
  final DateTime? createdAt;
  final bool dangling;
  final bool inUse;

  DockerImage({
    required this.id,
    required this.repository,
    required this.tag,
    required this.size,
    this.createdAt,
    this.dangling = false,
    this.inUse = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'repository': repository,
    'tag': tag,
    'size': size,
    'createdAt': createdAt?.toIso8601String(),
    'dangling': dangling,
    'inUse': inUse,
  };

  factory DockerImage.fromJson(Map<String, dynamic> json) {
    return DockerImage(
      id: json['id'] as String? ?? '',
      repository: json['repository'] as String? ?? '',
      tag: json['tag'] as String? ?? '',
      size: json['size'] as String? ?? '',
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String)
          : null,
      dangling: json['dangling'] as bool? ?? false,
      inUse: json['inUse'] as bool? ?? false,
    );
  }
}
