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
    this.maxShiftFraction = 0.055,
  });

  /// Fração da largura da imagem no pico de intensidade.
  final double maxShiftFraction;

  @override
  Set<BodyAdjustmentType> get supportedTypes => {
        BodyAdjustmentType.waistSlim,
        BodyAdjustmentType.torsoSlim,
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

    final topMid = Offset(
      (leftShoulder.dx + rightShoulder.dx) * 0.5,
      (leftShoulder.dy + rightShoulder.dy) * 0.5,
    );
    final bottomMid = Offset(
      (leftHip.dx + rightHip.dx) * 0.5,
      (leftHip.dy + rightHip.dy) * 0.5,
    );
    final shoulderY = topMid.dy;
    final hipY = bottomMid.dy;
    final span = math.max(hipY - shoulderY, 1.0);

    final isWaistFocused =
        context.adjustment.type == BodyAdjustmentType.waistSlim ||
            context.adjustment.type == BodyAdjustmentType.bellyReduce;
    final shiftPx = context.imageSize.width * maxShiftFraction * intensity;
    final halfWidth = context.imageSize.width * 0.22;

    final mesh = context.mesh;
    for (var i = 0; i < mesh.vertexCount; i++) {
      final region = mesh.regionAtVertex(i);
      final regionWeight = switch (region) {
        BodyRegion.waist => 1.0,
        BodyRegion.torso when !isWaistFocused => 0.75,
        BodyRegion.chest when !isWaistFocused => 0.45,
        BodyRegion.hip when isWaistFocused => 0.35,
        BodyRegion.butt when isWaistFocused => 0.2,
        _ => context.regionMatches(region) ? 0.5 : 0.0,
      };
      if (regionWeight <= 0) {
        continue;
      }

      final point = Offset(mesh.vertices[i * 2], mesh.vertices[i * 2 + 1]);
      final t = ((point.dy - shoulderY) / span).clamp(0.0, 1.0);
      // Pico no miolo da cintura; torso slim mais plano.
      final profile = isWaistFocused
          ? _waistProfile(t)
          : (0.45 + 0.45 * math.sin(math.pi * t.clamp(0.05, 0.95)));
      final axisFalloff = falloffAlongAxis(
        point: point,
        a: topMid,
        b: bottomMid,
        halfWidth: halfWidth,
      );
      if (axisFalloff <= 0 || profile <= 0) {
        continue;
      }

      final inward = inwardNormalTowardAxis(
        point: point,
        a: topMid,
        b: bottomMid,
      );
      if (inward == Offset.zero) {
        continue;
      }

      final w = regionWeight *
          profile *
          axisFalloff *
          mesh.weights[i].clamp(0.0, 1.0);
      accumulateDelta(
        deltas,
        i,
        inward.dx * shiftPx,
        inward.dy * shiftPx,
        w,
      );
    }
  }

  double _waistProfile(double t) {
    // Pico entre ~0.35 e ~0.65 do ombro→quadril.
    final centered = ((t - 0.5) / 0.22).abs();
    if (centered >= 1) {
      return 0.15;
    }
    final bell = 1.0 - centered * centered;
    return (0.35 + 0.65 * bell).clamp(0.0, 1.0);
  }
}
