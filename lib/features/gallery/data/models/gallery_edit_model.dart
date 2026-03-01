import '../../../../core/constants/operation_type.dart';
import '../../../../core/utils/server_date_utils.dart';

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
      createdAt: ServerDateUtils.parseServerDateOr(json['created_at'], DateTime.now()),
      status: json['status'] as String? ?? 'queued',
      operationType: json['operation_type'] as String?,
    );
  }

  /// Label amigável do tipo de operação (nunca exibir valor cru do banco).
  String get operationTypeLabel => OperationType.labelFrom(operationType);
}
