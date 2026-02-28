class GalleryEditModel {
  final String id;
  final String? imageUrl;
  final DateTime createdAt;
  final String status;
  final String? operationType;

  const GalleryEditModel({
    required this.id,
    this.imageUrl,
    required this.createdAt,
    required this.status,
    this.operationType,
  });

  factory GalleryEditModel.fromJson(Map<String, dynamic> json) {
    return GalleryEditModel(
      id: json['id'] as String,
      imageUrl: json['image_url'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      status: json['status'] as String? ?? 'queued',
      operationType: json['operation_type'] as String?,
    );
  }
}
