import 'beauty_preset.dart';

/// Item listado no marketplace público (Sprint 24).
class BeautyPresetMarketplaceEntry {
  final String remoteId;
  final String authorId;
  final String authorName;
  final String name;
  final BeautyPreset preset;
  final String? thumbnailUrl;
  final int installCount;
  final DateTime updatedAt;

  const BeautyPresetMarketplaceEntry({
    required this.remoteId,
    required this.authorId,
    required this.authorName,
    required this.name,
    required this.preset,
    this.thumbnailUrl,
    this.installCount = 0,
    required this.updatedAt,
  });

  factory BeautyPresetMarketplaceEntry.fromJson(Map<String, dynamic> json) {
    final presetJson = Map<String, dynamic>.from(
      json['preset_json'] as Map<String, dynamic>? ?? {},
    );
    final preset = BeautyPreset.fromJson(presetJson);
    final updatedRaw = json['updated_at'] as String?;

    return BeautyPresetMarketplaceEntry(
      remoteId: json['id'] as String,
      authorId: json['author_id'] as String,
      authorName: json['author_name'] as String? ?? 'Usuário',
      name: json['name'] as String? ?? preset.name,
      preset: preset,
      thumbnailUrl: json['thumbnail_url'] as String?,
      installCount: (json['install_count'] as num?)?.toInt() ?? 0,
      updatedAt: updatedRaw != null
          ? DateTime.parse(updatedRaw).toUtc()
          : DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }
}
