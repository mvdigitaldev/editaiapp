import '../models/beauty_preset.dart';
import 'bundled_preset_loader.dart';

/// Presets de fábrica incluídos no app (read-only, Sprint 21).
abstract final class BundledBeautyPresets {
  static const bundledIdPrefix = 'bundled_';

  static List<BeautyPreset>? _cache;
  static Future<List<BeautyPreset>>? _loading;

  static Future<List<BeautyPreset>> loadAll({
    BundledPresetLoader loader = const BundledPresetLoader(),
  }) {
    if (_cache != null) {
      return Future.value(_cache);
    }
    return _loading ??= loader.load().then((presets) {
      _cache = List<BeautyPreset>.unmodifiable(presets);
      return _cache!;
    });
  }

  static List<BeautyPreset> get all {
    final cached = _cache;
    if (cached == null) {
      throw StateError(
        'BundledBeautyPresets.loadAll() must be called before accessing all',
      );
    }
    return cached;
  }

  static Set<String> get ids => all.map((preset) => preset.id).toSet();

  static bool isBundled(String id) => id.startsWith(bundledIdPrefix);

  static BeautyPreset? findById(String id) {
    final cached = _cache;
    if (cached == null) {
      return null;
    }
    for (final preset in cached) {
      if (preset.id == id) {
        return preset;
      }
    }
    return null;
  }

  /// Apenas para testes — injeta cache sem assets.
  static void debugSetCache(List<BeautyPreset> presets) {
    _cache = List<BeautyPreset>.unmodifiable(presets);
    _loading = null;
  }

  static void debugResetCache() {
    _cache = null;
    _loading = null;
  }
}
