class PhotoEdit {
  final String id;
  final String photoId;
  final String userId;
  final String editType;
  final Map<String, dynamic>? editParams;
  final String? editedStoragePath;
  final String status; // 'pending', 'processing', 'completed', 'failed'
  final String? errorMessage;
  final String? aiJobId;
  final DateTime createdAt;
  final DateTime? completedAt;

  PhotoEdit({
    required this.id,
    required this.photoId,
    required this.userId,
    required this.editType,
    this.editParams,
    this.editedStoragePath,
    required this.status,
    this.errorMessage,
    this.aiJobId,
    required this.createdAt,
    this.completedAt,
  });
}
