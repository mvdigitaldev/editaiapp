import 'dart:typed_data';
import 'dart:ui';

import '../models/body_adjustment.dart';
import '../models/body_joint.dart';
import '../models/body_region.dart';
import 'body_region_deformation_strategy.dart';

/// Expande o peito para fora do eixo medial (banda ombro→cintura alta).
class ChestStrategy extends BodyRegionDeformationStrategy
    with RegionDeformationMath {
  const ChestStrategy({this.maxShiftFraction = 0.038});

  final double maxShiftFraction;

  @override
  Set<BodyAdjustmentType> get supportedTypes => {
        BodyAdjustmentType.chestExpand,
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
    if (leftShoulder == null || rightShoulder == null) {
      return;
    }

    final midlineX = (leftShoulder.dx + rightShoulder.dx) * 0.5;
    final shoulderY = (leftShoulder.dy + rightShoulder.dy) * 0.5;
    final hipY = leftHip != null && rightHip != null
        ? (leftHip.dy + rightHip.dy) * 0.5
        : shoulderY + context.imageSize.height * 0.28;
    final span = (hipY - shoulderY).abs().clamp(1.0, double.infinity);
    final shiftPx = context.imageSize.width * maxShiftFraction * intensity;
    final bandHalf = context.imageSize.height * 0.1;

    final mesh = context.mesh;
    for (var i = 0; i < mesh.vertexCount; i++) {
      final region = mesh.regionAtVertex(i);
      final regionWeight = switch (region) {
        BodyRegion.chest => 1.0,
        BodyRegion.shoulders => 0.55,
        BodyRegion.torso => 0.4,
        BodyRegion.waist => 0.15,
        _ => context.regionMatches(region) ? 0.35 : 0.0,
      };
      if (regionWeight <= 0) {
        continue;
      }

      final point = Offset(mesh.vertices[i * 2], mesh.vertices[i * 2 + 1]);
      final t = ((point.dy - shoulderY) / span).clamp(0.0, 1.0);
      // Pico alto no peito (~0.15–0.45 do ombro→quadril).
      final profile = ((t - 0.28).abs() < 0.2) ? 1.0 : 0.35;
      final verticalDist = (point.dy - (shoulderY + span * 0.28)).abs();
      if (verticalDist > bandHalf * 1.5) {
        continue;
      }
      final band = 1.0 - (verticalDist / (bandHalf * 1.5)).clamp(0.0, 1.0);
      final outward = horizontalOutwardFromMidline(
        point: point,
        midlineX: midlineX,
      );
      if (outward == Offset.zero) {
        continue;
      }

      final w = regionWeight *
          profile *
          band *
          band *
          (3 - 2 * band) *
          softVertexWeight(mesh.weights[i]);
      accumulateDelta(
        deltas,
        i,
        outward.dx * shiftPx,
        outward.dy * shiftPx,
        w,
      );
    }
  }
}
