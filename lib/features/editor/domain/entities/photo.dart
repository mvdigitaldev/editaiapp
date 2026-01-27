class Photo {
  final String id;
  final String userId;
  final String originalFilename;
  final String originalStoragePath;
  final int fileSizeBytes;
  final int? width;
  final int? height;
  final String? mimeType;
  final Map<String, dynamic>? metadata;
  final DateTime createdAt;
  final DateTime updatedAt;

  Photo({
    required this.id,
    required this.userId,
    required this.originalFilename,
    required this.originalStoragePath,
    required this.fileSizeBytes,
    this.width,
    this.height,
    this.mimeType,
    this.metadata,
    required this.createdAt,
    required this.updatedAt,
  });
}
