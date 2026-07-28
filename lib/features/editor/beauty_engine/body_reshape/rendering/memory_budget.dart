import '../../models/image_source.dart';
import '../../performance/adaptive_preview_policy.dart';

/// Orçamento de memória do Beauty Engine (docs/beauty/09-performance.md).
///
/// Sprint 13: export tiled deve permanecer abaixo de [exportPeakBytes].
abstract final class MemoryBudget {
  /// Pico permitido em preview interativo (mid-range).
  static const previewPeakBytes = 512 * 1024 * 1024;

  /// Pico permitido em export full / tiled.
  static const exportPeakBytes = 768 * 1024 * 1024;

  /// Limiar a partir do qual o export deve ser tiled.
  static const tiledExportMegapixels =
      AdaptivePreviewPolicy.tiledExportMegapixelThreshold;

  /// Halo padrão (px) para tiles de warp — cobre deslocamento típico + margem.
  static const defaultTileHaloPx = 64;

  /// Halo máximo (px) derivado do campo.
  static const maxTileHaloPx = 192;

  /// Estima bytes RGBA de uma imagem.
  static int rgbaBytes(int width, int height) => width * height * 4;

  /// Estimativa de pico do export tiled: source + output + 1 tile expandido.
  static int estimateTiledExportPeakBytes({
    required int fullWidth,
    required int fullHeight,
    int tileSize = AdaptivePreviewPolicy.tileSizePx,
    int haloPx = defaultTileHaloPx,
  }) {
    final source = rgbaBytes(fullWidth, fullHeight);
    final output = source;
    final expand = tileSize + 2 * haloPx;
    final tile = rgbaBytes(expand, expand);
    // Deslocamento/máscara em grade (~pequenos) + overhead nativo ~16 MB.
    const mapsOverhead = 16 * 1024 * 1024;
    return source + output + tile + mapsOverhead;
  }

  /// True se a imagem deve usar export tiled (> 8MP).
  static bool requiresTiledExport(ImageSource source) =>
      AdaptivePreviewPolicy.shouldUseTiledExport(source);

  /// True se o pico estimado cabe no orçamento de export.
  static bool fitsExportBudget({
    required int fullWidth,
    required int fullHeight,
    int tileSize = AdaptivePreviewPolicy.tileSizePx,
    int haloPx = defaultTileHaloPx,
  }) {
    return estimateTiledExportPeakBytes(
          fullWidth: fullWidth,
          fullHeight: fullHeight,
          tileSize: tileSize,
          haloPx: haloPx,
        ) <=
        exportPeakBytes;
  }

  /// Halo em px a partir do deslocamento máximo do campo.
  static int haloForMaxDisplacement(double maxDisplacementPx) {
    final raw = maxDisplacementPx.ceil() + 8;
    if (raw < defaultTileHaloPx) {
      return defaultTileHaloPx;
    }
    if (raw > maxTileHaloPx) {
      return maxTileHaloPx;
    }
    return raw;
  }
}
