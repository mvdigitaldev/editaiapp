import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../models/body_adjustment.dart';
import '../models/body_joint.dart';
import '../models/body_region.dart';
import 'body_region_deformation_strategy.dart';

/// Estreita a cintura em direção ao eixo medial do torso.
class WaistStrategy extends BodyRegionDeformationStrategy
    with RegionDeformationMath {
  const WaistStrategy({
    this.maxShiftFraction = 0.17,
  });

  /// Fração máxima da semi-largura local no pico de intensidade.
  final double maxShiftFraction;

  @override
  Set<BodyAdjustmentType> get supportedTypes => {
        BodyAdjustmentType.waistSlim,
        BodyAdjustmentType.torsoSlim,
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
    final shoulderY = topMid.dy;
    final hipY = bottomMid.dy;
    final span = math.max(hipY - shoulderY, 1.0);

    final isWaistFocused =
        context.adjustment.type == BodyAdjustmentType.waistSlim;
    final fallbackHalfWidth = context.imageSize.width * 0.12;
    final hasContour = context.torsoContour != null &&
        !(context.torsoContour!.isEmpty);
    final intensityScale = hasContour ? 1.0 : 0.35;
    final effectiveIntensity = intensity * intensityScale;

    final mesh = context.mesh;
    for (var i = 0; i < mesh.vertexCount; i++) {
      final region = mesh.regionAtVertex(i);
      final regionWeight = switch (region) {
        BodyRegion.waist => 1.0,
        // torso sempre participa do slim — evita buracos quando a classificação
        // cai em "torso" no miolo ou perto dos braços.
        BodyRegion.torso => isWaistFocused
            ? (hasContour ? 0.85 : 0.45)
            : (hasContour ? 0.65 : 0.3),
        BodyRegion.chest => isWaistFocused
            ? (hasContour ? 0.25 : 0.1)
            : (hasContour ? 0.35 : 0.15),
        BodyRegion.hip when isWaistFocused => hasContour ? 0.35 : 0.15,
        BodyRegion.butt when isWaistFocused => 0.15,
        _ => context.regionMatches(region) ? 0.4 : 0.0,
      };
      if (regionWeight <= 0) {
        continue;
      }

      final point = Offset(mesh.vertices[i * 2], mesh.vertices[i * 2 + 1]);
      final t = ((point.dy - shoulderY) / span).clamp(0.0, 1.0);
      final profile = isWaistFocused
          ? _waistProfile(t)
          : (0.45 + 0.45 * math.sin(math.pi * t.clamp(0.05, 0.95)));
      if (profile <= 0) {
        continue;
      }

      final band = context.torsoContour?.sampleAt(t);
      final halfWidth = band?.halfWidth ?? fallbackHalfWidth;
      final midlineX = band?.midlineX ??
          (topMid.dx + (bottomMid.dx - topMid.dx) * t);

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

  double _waistProfile(double t) {
    // Pico entre ~0.38 e ~0.62 do ombro→quadril (miolo da cintura).
    final centered = ((t - 0.5) / 0.2).abs();
    if (centered >= 1) {
      return 0.12;
    }
    final bell = 1.0 - centered * centered;
    return (0.35 + 0.65 * bell).clamp(0.0, 1.0);
  }
}
