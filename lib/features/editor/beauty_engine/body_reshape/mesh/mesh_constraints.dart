import 'dart:ui';

import '../models/body_region.dart';

/// Limites anatômicos e geométricos aplicados antes/depois da deformação.
class MeshConstraints {
  /// Fração da menor dimensão da imagem: deslocamento máximo por região.
  final Map<BodyRegion, double> maxDisplacementFraction;

  /// Área² mínima aceitável (|2×área|) para um triângulo após deformação.
  final double minTriangleArea2;

  /// Vértices com weight ≤ limiar são tratados como borda fixa.
  final double boundaryPinWeightThreshold;

  /// Iterações de anti-folding (escala global do delta se houver inversão).
  final int antiFoldIterations;

  /// Mistura de suavização laplaciana nos deltas (0 = off, 1 = full).
  final double laplacianBlend;

  /// Passes de suavização restrita (bordas fixas).
  final int laplacianPasses;

  const MeshConstraints({
    this.maxDisplacementFraction = defaultMaxDisplacementFraction,
    this.minTriangleArea2 = 1e-4,
    // Só pinar fundo verdadeiro — a silhueta (peso ~0.85+) precisa se mover.
    this.boundaryPinWeightThreshold = 0.05,
    this.antiFoldIterations = 8,
    // Blend alto achata o pico do delta na borda da silhueta (efeito invisível).
    this.laplacianBlend = 0.2,
    this.laplacianPasses = 2,
  })  : assert(minTriangleArea2 >= 0),
        assert(boundaryPinWeightThreshold >= 0 &&
            boundaryPinWeightThreshold <= 1),
        assert(antiFoldIterations >= 0),
        assert(laplacianBlend >= 0 && laplacianBlend <= 1),
        assert(laplacianPasses >= 0);

  static const defaultMaxDisplacementFraction = <BodyRegion, double>{
    BodyRegion.waist: 0.08,
    BodyRegion.hip: 0.055,
    BodyRegion.chest: 0.035,
    BodyRegion.butt: 0.035,
    BodyRegion.torso: 0.03,
    BodyRegion.leftArm: 0.028,
    BodyRegion.rightArm: 0.028,
    BodyRegion.leftForearm: 0.024,
    BodyRegion.rightForearm: 0.024,
    BodyRegion.leftThigh: 0.032,
    BodyRegion.rightThigh: 0.032,
    BodyRegion.leftCalf: 0.028,
    BodyRegion.rightCalf: 0.028,
    BodyRegion.shoulders: 0.03,
    BodyRegion.neck: 0.02,
  };

  static const conservative = MeshConstraints(
    maxDisplacementFraction: {
      BodyRegion.waist: 0.03,
      BodyRegion.hip: 0.028,
      BodyRegion.chest: 0.024,
      BodyRegion.butt: 0.024,
      BodyRegion.torso: 0.02,
      BodyRegion.leftArm: 0.018,
      BodyRegion.rightArm: 0.018,
      BodyRegion.leftForearm: 0.016,
      BodyRegion.rightForearm: 0.016,
      BodyRegion.leftThigh: 0.022,
      BodyRegion.rightThigh: 0.022,
      BodyRegion.leftCalf: 0.018,
      BodyRegion.rightCalf: 0.018,
      BodyRegion.shoulders: 0.02,
      BodyRegion.neck: 0.014,
    },
    antiFoldIterations: 10,
    laplacianBlend: 0.45,
    laplacianPasses: 3,
  );

  double maxDisplacementPx(BodyRegion region, Size imageSize) {
    final fraction = maxDisplacementFraction[region] ?? 0.03;
    final minDim = imageSize.width < imageSize.height
        ? imageSize.width
        : imageSize.height;
    return minDim * fraction;
  }
}
