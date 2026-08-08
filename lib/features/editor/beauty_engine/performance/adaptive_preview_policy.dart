import 'dart:math' as math;

import '../models/image_source.dart';
import 'device_capability.dart';

/// Limites de resolução de preview conforme `09-performance.md` (Sprint 25).
abstract final class AdaptivePreviewPolicy {
  /// Teto de resolução na ENTRADA (Sprint 0 do SDK facial): fotos acima
  /// disso (ex.: 100MP+ de sensores Samsung) são reduzidas no load para
  /// evitar OOM antes de qualquer análise. Export usa a imagem normalizada.
  static const inputMaxEdge = 4096;
  static const selfieMaxEdge = 720;
  static const photoMaxEdge = 1080;
  /// Preview interativo de body warp — prioriza latência (~800ms → <200ms).
  static const bodyWarpInteractiveMaxEdge = 800;
  /// Export / preview final (qualidade).
  static const bodyWarpMaxEdge = 1280;
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

  /// Preview com teto do tier de hardware (Sprint 6).
  static int maxEdgeForSourceWithProfile(
    ImageSource source,
    DeviceCapabilityProfile profile,
  ) {
    final base = maxEdgeForSource(source);
    return math.min(base, profile.previewMaxEdge);
  }

  static int maxEdgeForBodyWarpPreviewWithProfile(
    ImageSource source,
    DeviceCapabilityProfile profile,
  ) {
    final base = maxEdgeForBodyWarpPreview(source);
    return math.min(base, profile.previewMaxEdge);
  }

  static int tileSizeForProfile(DeviceCapabilityProfile profile) {
    return profile.exportTileSizePx;
  }

  static int maxEdgeForBodyWarpPreview(ImageSource source) {
    final base = maxEdgeForSource(source);
    return math.max(base, bodyWarpInteractiveMaxEdge);
  }

  static int maxEdgeForBodyWarpExport(ImageSource source) {
    final base = maxEdgeForSource(source);
    return math.max(base, bodyWarpMaxEdge);
  }

  static bool shouldUseTiledExport(ImageSource source) {
    return megapixels(source) > tiledExportMegapixelThreshold;
  }

  static const tiledExportMegapixelThreshold = 8.0;
  static const tileSizePx = 2048;
}
