import 'dart:math' as math;
import 'dart:ui';

import '../models/body_reshape_request.dart';

/// Orçamento de resolução da malha corporal adaptativa.
class MeshResolutionProfile {
  final WarpQuality quality;
  final double baseCellPx;
  final double minCellPx;
  final double contourSpacingPx;
  final int maxVertices;
  final double densityScale;

  const MeshResolutionProfile({
    required this.quality,
    required this.baseCellPx,
    required this.minCellPx,
    required this.contourSpacingPx,
    required this.maxVertices,
    required this.densityScale,
  })  : assert(baseCellPx > 0),
        assert(minCellPx > 0),
        assert(contourSpacingPx > 0),
        assert(maxVertices > 0),
        assert(densityScale > 0);

  /// Deriva LOD a partir do perfil de qualidade e do tamanho da imagem.
  factory MeshResolutionProfile.fromQuality(
    WarpQualityProfile qualityProfile,
    Size imageSize,
  ) {
    final minDim = math.min(imageSize.width, imageSize.height);
    final scale = qualityProfile.meshDensityScale;

    return switch (qualityProfile.quality) {
      WarpQuality.interactive => MeshResolutionProfile(
          quality: WarpQuality.interactive,
          baseCellPx: (minDim / 28).clamp(18, 36) / scale,
          minCellPx: (minDim / 70).clamp(8, 16) / scale,
          contourSpacingPx: (minDim / 55).clamp(10, 20) / scale,
          maxVertices: (2200 * scale).round().clamp(800, 4000),
          densityScale: scale,
        ),
      WarpQuality.preview => MeshResolutionProfile(
          quality: WarpQuality.preview,
          baseCellPx: (minDim / 40).clamp(12, 28) / scale,
          minCellPx: (minDim / 90).clamp(5, 12) / scale,
          contourSpacingPx: (minDim / 70).clamp(6, 14) / scale,
          maxVertices: (6500 * scale).round().clamp(2000, 10000),
          densityScale: scale,
        ),
      WarpQuality.export => MeshResolutionProfile(
          quality: WarpQuality.export,
          baseCellPx: (minDim / 55).clamp(8, 18) / scale,
          minCellPx: (minDim / 120).clamp(3, 8) / scale,
          contourSpacingPx: (minDim / 95).clamp(4, 10) / scale,
          maxVertices: (14000 * scale).round().clamp(4000, 25000),
          densityScale: scale,
        ),
    };
  }
}
