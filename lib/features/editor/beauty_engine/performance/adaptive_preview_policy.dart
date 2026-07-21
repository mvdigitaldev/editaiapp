import '../models/image_source.dart';

/// Limites de resolução de preview conforme `09-performance.md` (Sprint 25).
abstract final class AdaptivePreviewPolicy {
  static const selfieMaxEdge = 720;
  static const photoMaxEdge = 1080;
  static const selfieMegapixelCap = 1.0;
  static const photo4MegapixelCap = 5.0;

  static double megapixels(ImageSource source) {
    return (source.width * source.height) / 1e6;
  }

  /// Retorna o maior lado permitido para preview interativo.
  static int maxEdgeForSource(ImageSource source) {
    final mp = megapixels(source);
    if (mp <= selfieMegapixelCap) {
      return selfieMaxEdge;
    }
    return photoMaxEdge;
  }

  static bool shouldUseTiledExport(ImageSource source) {
    return megapixels(source) > tiledExportMegapixelThreshold;
  }

  static const tiledExportMegapixelThreshold = 8.0;
  static const tileSizePx = 2048;
}
