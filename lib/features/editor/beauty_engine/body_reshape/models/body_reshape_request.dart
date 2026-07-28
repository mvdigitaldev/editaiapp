import 'dart:ui';

/// Nível de qualidade solicitado ao Body Reshape V2.
enum WarpQuality {
  interactive,
  preview,
  export,
}

/// Orçamento declarativo usado por malha, mapas e refinamentos futuros.
class WarpQualityProfile {
  final WarpQuality quality;
  final double meshDensityScale;
  final double mapResolutionScale;
  final int refinementIterations;

  const WarpQualityProfile({
    required this.quality,
    required this.meshDensityScale,
    required this.mapResolutionScale,
    required this.refinementIterations,
  })  : assert(meshDensityScale > 0),
        assert(mapResolutionScale > 0),
        assert(refinementIterations >= 0);

  static const interactive = WarpQualityProfile(
    quality: WarpQuality.interactive,
    meshDensityScale: 0.5,
    mapResolutionScale: 0.5,
    refinementIterations: 1,
  );

  static const preview = WarpQualityProfile(
    quality: WarpQuality.preview,
    meshDensityScale: 0.75,
    mapResolutionScale: 0.75,
    refinementIterations: 2,
  );

  static const export = WarpQualityProfile(
    quality: WarpQuality.export,
    meshDensityScale: 1,
    mapResolutionScale: 1,
    refinementIterations: 4,
  );

  static WarpQualityProfile forQuality(WarpQuality quality) {
    return switch (quality) {
      WarpQuality.interactive => interactive,
      WarpQuality.preview => preview,
      WarpQuality.export => export,
    };
  }
}

/// Entrada pública e imutável para a etapa de planejamento.
class BodyReshapeRequest {
  final Size imageSize;
  final Map<String, double> parameters;
  final WarpQualityProfile qualityProfile;

  const BodyReshapeRequest({
    required this.imageSize,
    required this.parameters,
    this.qualityProfile = WarpQualityProfile.preview,
  });
}
