import '../../domain/entities/photo.dart';

class PhotoModel extends Photo {
  PhotoModel({
    required super.id,
    required super.userId,
    required super.originalFilename,
    required super.originalStoragePath,
    required super.fileSizeBytes,
    super.width,
    super.height,
    super.mimeType,
    super.metadata,
    required super.createdAt,
    required super.updatedAt,
  });

  factory PhotoModel.fromJson(Map<String, dynamic> json) {
    return PhotoModel(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      originalFilename: json['original_filename'] as String,
      originalStoragePath: json['original_storage_path'] as String,
      fileSizeBytes: json['file_size_bytes'] as int,
      width: json['width'] as int?,
      height: json['height'] as int?,
      mimeType: json['mime_type'] as String?,
      metadata: json['metadata'] as Map<String, dynamic>?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'original_filename': originalFilename,
      'original_storage_path': originalStoragePath,
      'file_size_bytes': fileSizeBytes,
      'width': width,
      'height': height,
      'mime_type': mimeType,
      'metadata': metadata,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  Photo toEntity() {
    return Photo(
      id: id,
      userId: userId,
      originalFilename: originalFilename,
      originalStoragePath: originalStoragePath,
      fileSizeBytes: fileSizeBytes,
      width: width,
      height: height,
      mimeType: mimeType,
      metadata: metadata,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}
