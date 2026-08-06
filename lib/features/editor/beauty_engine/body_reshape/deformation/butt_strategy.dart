import 'dart:typed_data';
import 'dart:ui';

import '../models/body_adjustment.dart';
import '../models/body_joint.dart';
import '../models/body_region.dart';
import 'body_region_deformation_strategy.dart';

/// Expande o glúteo (banda abaixo do marco do quadril).
class ButtStrategy extends BodyRegionDeformationStrategy
    with RegionDeformationMath {
  const ButtStrategy({this.maxShiftFraction = 0.036});

  final double maxShiftFraction;

  @override
  Set<BodyAdjustmentType> get supportedTypes => {
        BodyAdjustmentType.buttExpand,
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

    final leftHip = context.landmarkPx(BodyJoint.leftHip);
    final rightHip = context.landmarkPx(BodyJoint.rightHip);
    if (leftHip == null || rightHip == null) {
      return;
    }

    final midlineX = (leftHip.dx + rightHip.dx) * 0.5;
    final hipY = (leftHip.dy + rightHip.dy) * 0.5;
    final shiftPx = context.imageSize.width * maxShiftFraction * intensity;
    final bandHalf = context.imageSize.height * 0.11;

    final mesh = context.mesh;
    for (var i = 0; i < mesh.vertexCount; i++) {
      final region = mesh.regionAtVertex(i);
      final regionWeight = switch (region) {
        BodyRegion.butt => 1.0,
        BodyRegion.hip => 0.55,
        BodyRegion.leftThigh || BodyRegion.rightThigh => 0.3,
        _ => context.regionMatches(region) ? 0.35 : 0.0,
      };
      if (regionWeight <= 0) {
        continue;
      }

      final point = Offset(mesh.vertices[i * 2], mesh.vertices[i * 2 + 1]);
      if (point.dy < hipY - bandHalf * 0.35) {
        continue;
      }
      final verticalDist = (point.dy - (hipY + bandHalf * 0.35)).abs();
      if (verticalDist > bandHalf * 1.4) {
        continue;
      }
      final band = 1.0 - (verticalDist / (bandHalf * 1.4)).clamp(0.0, 1.0);
      final bandSmooth = band * band * (3 - 2 * band);

      final outward = horizontalOutwardFromMidline(
        point: point,
        midlineX: midlineX,
      );
      if (outward == Offset.zero) {
        continue;
      }

      final lateral = ((point.dx - midlineX).abs() /
              (context.imageSize.width * 0.16))
          .clamp(0.0, 1.0);
      final w = regionWeight *
          bandSmooth *
          (0.4 + 0.6 * lateral) *
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
