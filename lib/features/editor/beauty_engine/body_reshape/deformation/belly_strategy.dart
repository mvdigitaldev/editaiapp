import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../models/body_adjustment.dart';
import '../models/body_joint.dart';
import '../models/body_region.dart';
import 'body_region_deformation_strategy.dart';

/// Reduz a barriga (banda média-baixa do torso) em direção ao eixo medial.
class BellyStrategy extends BodyRegionDeformationStrategy
    with RegionDeformationMath {
  const BellyStrategy({this.maxShiftFraction = 0.18});

  /// Fração máxima da semi-largura local no pico de intensidade.
  final double maxShiftFraction;

  @override
  Set<BodyAdjustmentType> get supportedTypes => {
        BodyAdjustmentType.bellyReduce,
      };

  @override
  void apply({
    required RegionDeformationContext context,
    required Float32List deltas,
  }) {
    final intensity = context.intensity;
    if (intensity <= 0) {
      return;
    }

    final leftShoulder = context.landmarkPx(BodyJoint.leftShoulder);
    final rightShoulder = context.landmarkPx(BodyJoint.rightShoulder);
    final leftHip = context.landmarkPx(BodyJoint.leftHip);
    final rightHip = context.landmarkPx(BodyJoint.rightHip);
    if (leftShoulder == null ||
        rightShoulder == null ||
        leftHip == null ||
        rightHip == null) {
      return;
    }

    final topMid = context.torsoContour?.topMid ??
        Offset(
          (leftShoulder.dx + rightShoulder.dx) * 0.5,
          (leftShoulder.dy + rightShoulder.dy) * 0.5,
        );
    final bottomMid = context.torsoContour?.bottomMid ??
        Offset(
          (leftHip.dx + rightHip.dx) * 0.5,
          (leftHip.dy + rightHip.dy) * 0.5,
        );
    final span = math.max(bottomMid.dy - topMid.dy, 1.0);
    final fallbackHalfWidth = context.imageSize.width * 0.12;
    final hasContour = context.torsoContour != null &&
        !(context.torsoContour!.isEmpty);
    // Sem contorno confiável: não espalhar pelo torso — reduz intensidade.
    final intensityScale = hasContour ? 1.0 : 0.35;
    final effectiveIntensity = intensity * intensityScale;

    final mesh = context.mesh;
    for (var i = 0; i < mesh.vertexCount; i++) {
      final region = mesh.regionAtVertex(i);
      final regionWeight = switch (region) {
        BodyRegion.waist => 1.0,
        BodyRegion.torso => hasContour ? 0.9 : 0.45,
        BodyRegion.hip => hasContour ? 0.4 : 0.18,
        BodyRegion.chest => 0.15,
        _ => context.regionMatches(region) ? 0.3 : 0.0,
      };
      if (regionWeight <= 0) {
        continue;
      }

      final point = Offset(mesh.vertices[i * 2], mesh.vertices[i * 2 + 1]);
      final t = ((point.dy - topMid.dy) / span).clamp(0.0, 1.0);
      // Pico alinhado à faixa waist (~0.50–0.62 ombro→quadril).
      final centered = ((t - 0.56) / 0.16).abs();
      final profile =
          centered >= 1 ? 0.08 : (0.25 + 0.75 * (1 - centered * centered));
      if (profile <= 0) {
        continue;
      }

      final band = context.torsoContour?.sampleAt(t);
      final halfWidth = band?.halfWidth ?? fallbackHalfWidth;
      final midlineX =
          band?.midlineX ?? (topMid.dx + (bottomMid.dx - topMid.dx) * t);

      // Mais peso nas bordas; miolo move pouco (evita pinagem da borda matte).
      final distFromMid = (point.dx - midlineX).abs();
      final radial =
          (distFromMid / math.max(halfWidth, 1.0)).clamp(0.0, 1.15);
      final edgeFalloff = hasContour
          ? (0.18 + 0.82 * (radial * radial).clamp(0.0, 1.0))
          : (0.08 + 0.5 * (radial * radial).clamp(0.0, 1.0));

      final inward = Offset(midlineX - point.dx, 0);
      final dist = inward.distance;
      if (dist < 1e-6) {
        continue;
      }
      final dir = Offset(inward.dx / dist, 0);
      final localShift = halfWidth * maxShiftFraction * effectiveIntensity;
      final w = regionWeight *
          profile *
          edgeFalloff *
          softConfidence(band?.confidence) *
          softVertexWeight(mesh.weights[i]);
      accumulateDelta(
        deltas,
        i,
        dir.dx * localShift,
        dir.dy * localShift,
        w,
      );
    }
  }
}
