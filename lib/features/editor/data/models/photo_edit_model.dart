import '../../../../core/utils/server_date_utils.dart';
import '../../domain/entities/photo_edit.dart';

class PhotoEditModel extends PhotoEdit {
  PhotoEditModel({
    required super.id,
    required super.photoId,
    required super.userId,
    required super.editType,
    super.editParams,
    super.editedStoragePath,
    required super.status,
    super.errorMessage,
    super.aiJobId,
    required super.createdAt,
    super.completedAt,
  });

  factory PhotoEditModel.fromJson(Map<String, dynamic> json) {
    return PhotoEditModel(
      id: json['id'] as String,
      photoId: json['photo_id'] as String,
      userId: json['user_id'] as String,
      editType: json['edit_type'] as String,
      editParams: json['edit_params'] as Map<String, dynamic>?,
      editedStoragePath: json['edited_storage_path'] as String?,
      status: json['status'] as String,
      errorMessage: json['error_message'] as String?,
      aiJobId: json['ai_job_id'] as String?,
      createdAt: ServerDateUtils.parseServerDateOr(json['created_at'], DateTime.now()),
      completedAt: ServerDateUtils.parseServerDate(json['completed_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'photo_id': photoId,
      'user_id': userId,
      'edit_type': editType,
      'edit_params': editParams,
      'edited_storage_path': editedStoragePath,
      'status': status,
      'error_message': errorMessage,
      'ai_job_id': aiJobId,
      'created_at': createdAt.toIso8601String(),
      'completed_at': completedAt?.toIso8601String(),
    };
  }

  PhotoEdit toEntity() {
    return PhotoEdit(
      id: id,
      photoId: photoId,
      userId: userId,
      editType: editType,
      editParams: editParams,
      editedStoragePath: editedStoragePath,
      status: status,
      errorMessage: errorMessage,
      aiJobId: aiJobId,
      createdAt: createdAt,
      completedAt: completedAt,
    );
  }
}
