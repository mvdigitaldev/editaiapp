import 'dart:typed_data';
import 'dart:ui';

import '../models/body_adjustment.dart';
import '../models/body_joint.dart';
import '../models/body_region.dart';
import 'body_region_deformation_strategy.dart';

/// Alarga ou estreita ombros horizontalmente a partir da midline.
class ShoulderStrategy extends BodyRegionDeformationStrategy
    with RegionDeformationMath {
  const ShoulderStrategy({this.maxShiftFraction = 0.04});

  final double maxShiftFraction;

  @override
  Set<BodyAdjustmentType> get supportedTypes => {
        BodyAdjustmentType.shoulderExpand,
        BodyAdjustmentType.shoulderReduce,
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
    if (leftShoulder == null || rightShoulder == null) {
      return;
    }

    final midlineX = (leftShoulder.dx + rightShoulder.dx) * 0.5;
    final shoulderY = (leftShoulder.dy + rightShoulder.dy) * 0.5;
    final expand =
        context.adjustment.type == BodyAdjustmentType.shoulderExpand;
    final shiftPx = context.imageSize.width * maxShiftFraction * intensity;
    final bandHalf = context.imageSize.height * 0.08;

    final mesh = context.mesh;
    for (var i = 0; i < mesh.vertexCount; i++) {
      final region = mesh.regionAtVertex(i);
      final regionWeight = switch (region) {
        BodyRegion.shoulders => 1.0,
        BodyRegion.chest => 0.45,
        BodyRegion.neck => 0.25,
        BodyRegion.leftArm || BodyRegion.rightArm => 0.2,
        _ => context.regionMatches(region) ? 0.35 : 0.0,
      };
      if (regionWeight <= 0) {
        continue;
      }

      final point = Offset(mesh.vertices[i * 2], mesh.vertices[i * 2 + 1]);
      final verticalDist = (point.dy - shoulderY).abs();
      if (verticalDist > bandHalf * 1.5) {
        continue;
      }
      final band = 1.0 - (verticalDist / (bandHalf * 1.5)).clamp(0.0, 1.0);
      final bandSmooth = band * band * (3 - 2 * band);

      final outward = horizontalOutwardFromMidline(
        point: point,
        midlineX: midlineX,
      );
      if (outward == Offset.zero) {
        continue;
      }

      final dir = expand ? 1.0 : -1.0;
      final w = regionWeight * bandSmooth * softVertexWeight(mesh.weights[i]);
      accumulateDelta(
        deltas,
        i,
        outward.dx * shiftPx * dir,
        outward.dy * shiftPx * dir,
        w,
      );
    }
  }
}
