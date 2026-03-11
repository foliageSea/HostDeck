class FileItem {
  final String filename;
  final String longname;
  final bool isDirectory;
  final int size;
  final DateTime? mtime;

  FileItem({
    required this.filename,
    required this.longname,
    required this.isDirectory,
    required this.size,
    this.mtime,
  });

  Map<String, dynamic> toJson() => {
    'filename': filename,
    'longname': longname,
    'isDirectory': isDirectory,
    'size': size,
    'mtime': mtime?.toIso8601String(),
  };
}
