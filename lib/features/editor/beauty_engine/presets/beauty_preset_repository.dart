import 'dart:convert';

import '../models/beauty_preset.dart';
import '../models/beauty_preset_marketplace_entry.dart';

/// Repositorio local de presets (Sprint 08+) com sync remoto opcional (Sprint 23/24).
abstract class BeautyPresetRepository {
  Future<List<BeautyPreset>> listPresets();

  Future<List<BeautyPreset>> listBundledPresets();

  Future<List<BeautyPreset>> listUserPresets();

  Future<BeautyPreset?> findById(String id);

  Future<void> savePreset(BeautyPreset preset);

  Future<void> deletePreset(String id);

  Future<String> exportPresetJson(String id);

  Future<BeautyPreset> importPresetJson(Map<String, dynamic> json);

  /// Salva preset e gera thumbnail JPEG local (Sprint 22).
  Future<BeautyPreset> savePresetWithThumbnail({
    required BeautyPreset preset,
    required List<int> previewJpegBytes,
  });

  /// Pull/push com Supabase — last-write-wins (Sprint 23).
  Future<void> syncWithRemote();

  /// Publica ou oculta preset no marketplace (Sprint 24).
  Future<BeautyPreset> setPresetPublic({
    required String id,
    required bool isPublic,
  });

  /// Lista presets públicos de outros usuários (Sprint 24).
  Future<List<BeautyPresetMarketplaceEntry>> listMarketplacePresets({
    int limit = 50,
    int offset = 0,
  });

  /// Instala preset público como cópia local (Sprint 24).
  Future<BeautyPreset> installMarketplacePreset(String remoteId);
}

/// Stub in-memory para testes isolados.
class BeautyPresetRepositoryStub implements BeautyPresetRepository {
  BeautyPresetRepositoryStub({List<BeautyPreset>? userPresets})
      : _userPresets = List<BeautyPreset>.from(userPresets ?? []);

  final List<BeautyPreset> _userPresets;

  @override
  Future<void> deletePreset(String id) async {
    _userPresets.removeWhere((preset) => preset.id == id);
  }

  @override
  Future<BeautyPreset?> findById(String id) async {
    for (final preset in _userPresets) {
      if (preset.id == id) {
        return preset;
      }
    }
    return null;
  }

  @override
  Future<String> exportPresetJson(String id) async {
    final preset = await findById(id);
    if (preset == null) {
      throw StateError('Preset not found: $id');
    }
    return jsonEncode(preset.toJson());
  }

  @override
  Future<BeautyPreset> importPresetJson(Map<String, dynamic> json) async {
    final preset = BeautyPreset.fromJson(json);
    await savePreset(preset);
    return preset;
  }

  @override
  Future<List<BeautyPreset>> listBundledPresets() async => const [];

  @override
  Future<List<BeautyPreset>> listPresets() async =>
      List<BeautyPreset>.unmodifiable(_userPresets);

  @override
  Future<List<BeautyPreset>> listUserPresets() async =>
      List<BeautyPreset>.unmodifiable(_userPresets);

  @override
  Future<void> savePreset(BeautyPreset preset) async {
    _userPresets.removeWhere((entry) => entry.id == preset.id);
    _userPresets.add(preset);
  }

  @override
  Future<BeautyPreset> savePresetWithThumbnail({
    required BeautyPreset preset,
    required List<int> previewJpegBytes,
  }) async {
    await savePreset(preset);
    return preset;
  }

  @override
  Future<void> syncWithRemote() async {}

  @override
  Future<BeautyPreset> setPresetPublic({
    required String id,
    required bool isPublic,
  }) async {
    final preset = await findById(id);
    if (preset == null) {
      throw StateError('Preset not found: $id');
    }
    final updated = preset.copyWith(isPublic: isPublic);
    await savePreset(updated);
    return updated;
  }

  @override
  Future<List<BeautyPresetMarketplaceEntry>> listMarketplacePresets({
    int limit = 50,
    int offset = 0,
  }) async =>
      const [];

  @override
  Future<BeautyPreset> installMarketplacePreset(String remoteId) async {
    throw UnimplementedError('Marketplace not available in stub');
  }
}
