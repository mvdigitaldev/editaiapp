import 'package:intl/intl.dart';

class EditDetailModel {
  final String id;
  final String userId;
  final String? imageId;
  final String? promptText;
  final String? promptTextOriginal;
  final String editCategory;
  final String editGoal;
  final String desiredStyle;
  final String status;
  final int? aiProcessingTimeMs;
  final int creditsUsed;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? operationType;
  final String? taskId;
  final String? imageUrl;
  final int? fileSize;
  final String? mimeType;
  final int? width;
  final int? height;

  const EditDetailModel({
    required this.id,
    required this.userId,
    this.imageId,
    this.promptText,
    this.promptTextOriginal,
    required this.editCategory,
    required this.editGoal,
    required this.desiredStyle,
    required this.status,
    this.aiProcessingTimeMs,
    required this.creditsUsed,
    required this.createdAt,
    required this.updatedAt,
    this.operationType,
    this.taskId,
    this.imageUrl,
    this.fileSize,
    this.mimeType,
    this.width,
    this.height,
  });

  factory EditDetailModel.fromJson(Map<String, dynamic> json) {
    return EditDetailModel(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      imageId: json['image_id'] as String?,
      promptText: json['prompt_text'] as String?,
      promptTextOriginal: json['prompt_text_original'] as String?,
      editCategory: json['edit_category'] as String? ?? 'other',
      editGoal: json['edit_goal'] as String? ?? 'enhance_details',
      desiredStyle: json['desired_style'] as String? ?? 'natural',
      status: json['status'] as String? ?? 'queued',
      aiProcessingTimeMs: json['ai_processing_time_ms'] as int?,
      creditsUsed: json['credits_used'] as int? ?? 0,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      operationType: json['operation_type'] as String?,
      taskId: json['task_id'] as String?,
      imageUrl: json['image_url'] as String?,
      fileSize: json['file_size'] as int?,
      mimeType: json['mime_type'] as String?,
      width: json['width'] as int?,
      height: json['height'] as int?,
    );
  }

  String get formattedCreatedAt =>
      DateFormat('d MMM yyyy, HH:mm', 'pt_BR').format(createdAt);

  String get formattedUpdatedAt =>
      DateFormat('d MMM yyyy, HH:mm', 'pt_BR').format(updatedAt);

  String get formattedFileSize {
    if (fileSize == null || fileSize! <= 0) return '—';
    if (fileSize! < 1024) return '$fileSize B';
    if (fileSize! < 1024 * 1024) return '${(fileSize! / 1024).toStringAsFixed(1)} KB';
    return '${(fileSize! / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String get dimensionsText {
    if (width != null && height != null && width! > 0 && height! > 0) {
      return '${width} x $height';
    }
    return '—';
  }

  String get editCategoryLabel {
    switch (editCategory) {
      case 'food':
        return 'Comida';
      case 'person':
        return 'Pessoa';
      case 'landscape':
        return 'Paisagem';
      case 'product':
        return 'Produto';
      case 'other':
      default:
        return 'Outro';
    }
  }

  String get editGoalLabel {
    switch (editGoal) {
      case 'improve_colors':
        return 'Melhorar cores';
      case 'change_background':
        return 'Mudar fundo';
      case 'remove_objects':
        return 'Remover objetos';
      case 'enhance_details':
        return 'Detalhar';
      case 'adjust_lighting':
        return 'Ajustar iluminação';
      default:
        return editGoal;
    }
  }

  String get desiredStyleLabel {
    switch (desiredStyle) {
      case 'natural':
        return 'Natural';
      case 'professional':
        return 'Profissional';
      case 'artistic':
        return 'Artístico';
      case 'realistic':
        return 'Realista';
      default:
        return desiredStyle;
    }
  }

  String get statusLabel {
    switch (status) {
      case 'queued':
        return 'Na fila';
      case 'processing':
        return 'Processando';
      case 'completed':
        return 'Concluído';
      case 'failed':
        return 'Falhou';
      default:
        return status;
    }
  }

  String get promptDisplay => promptText ?? promptTextOriginal ?? '—';

  String get processingTimeText {
    if (aiProcessingTimeMs == null || aiProcessingTimeMs! <= 0) return '—';
    if (aiProcessingTimeMs! < 1000) return '${aiProcessingTimeMs} ms';
    return '${(aiProcessingTimeMs! / 1000).toStringAsFixed(1)} s';
  }
}
