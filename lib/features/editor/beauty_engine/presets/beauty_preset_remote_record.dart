import '../models/beauty_preset.dart';

/// Linha remota em `beauty_presets` (Sprint 23).
class BeautyPresetRemoteRecord {
  final String id;
  final String userId;
  final String clientId;
  final String name;
  final BeautyPreset preset;
  final bool isPublic;
  final String? thumbnailUrl;
  final int installCount;
  final DateTime createdAt;
  final DateTime updatedAt;

  const BeautyPresetRemoteRecord({
    required this.id,
    required this.userId,
    required this.clientId,
    required this.name,
    required this.preset,
    this.isPublic = false,
    this.thumbnailUrl,
    this.installCount = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  factory BeautyPresetRemoteRecord.fromJson(Map<String, dynamic> json) {
    final presetJson = Map<String, dynamic>.from(
      json['preset_json'] as Map<String, dynamic>? ?? {},
    );
    final preset = BeautyPreset.fromJson(presetJson);

    return BeautyPresetRemoteRecord(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      clientId: json['client_id'] as String,
      name: json['name'] as String? ?? preset.name,
      preset: preset,
      isPublic: json['is_public'] as bool? ?? false,
      thumbnailUrl: json['thumbnail_url'] as String?,
      installCount: (json['install_count'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.parse(json['created_at'] as String).toUtc(),
      updatedAt: DateTime.parse(json['updated_at'] as String).toUtc(),
    );
  }

  Map<String, dynamic> toInsertJson({
    required String userId,
    required BeautyPreset preset,
    required String name,
    required bool isPublic,
    String? thumbnailUrl,
  }) {
    return {
      'user_id': userId,
      'client_id': preset.id,
      'name': name,
      'preset_json': preset.toJson(),
      'is_public': isPublic,
      if (thumbnailUrl != null) 'thumbnail_url': thumbnailUrl,
    };
  }

  Map<String, dynamic> toUpdateJson({
    required BeautyPreset preset,
    required String name,
    required bool isPublic,
    String? thumbnailUrl,
    bool clearThumbnailUrl = false,
  }) {
    return {
      'name': name,
      'preset_json': preset.toJson(),
      'is_public': isPublic,
      if (clearThumbnailUrl) 'thumbnail_url': null,
      if (!clearThumbnailUrl && thumbnailUrl != null)
        'thumbnail_url': thumbnailUrl,
    };
  }
}
