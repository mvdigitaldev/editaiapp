import 'dart:typed_data';
import 'dart:ui';

import '../models/body_adjustment.dart';
import '../models/body_joint.dart';
import '../models/body_region.dart';
import 'body_region_deformation_strategy.dart';

/// Alarga o quadril para fora do eixo medial.
class HipStrategy extends BodyRegionDeformationStrategy
    with RegionDeformationMath {
  const HipStrategy({
    this.maxShiftFraction = 0.04,
  });

  final double maxShiftFraction;

  @override
  Set<BodyAdjustmentType> get supportedTypes => {
        BodyAdjustmentType.hipExpand,
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
    final leftShoulder = context.landmarkPx(BodyJoint.leftShoulder);
    final rightShoulder = context.landmarkPx(BodyJoint.rightShoulder);
    if (leftHip == null || rightHip == null) {
      return;
    }

    final midlineX = (leftHip.dx + rightHip.dx) * 0.5;
    final hipY = (leftHip.dy + rightHip.dy) * 0.5;
    final shoulderY = leftShoulder != null && rightShoulder != null
        ? (leftShoulder.dy + rightShoulder.dy) * 0.5
        : hipY - context.imageSize.height * 0.2;
    final span = (hipY - shoulderY).abs().clamp(1.0, double.infinity);

    final shiftPx = context.imageSize.width * maxShiftFraction * intensity;
    final bandHalf = context.imageSize.height * 0.12;

    final mesh = context.mesh;
    for (var i = 0; i < mesh.vertexCount; i++) {
      final region = mesh.regionAtVertex(i);
      final regionWeight = switch (region) {
        BodyRegion.hip => 1.0,
        BodyRegion.butt => 0.55,
        BodyRegion.waist => 0.35,
        BodyRegion.leftThigh || BodyRegion.rightThigh => 0.25,
        _ => context.regionMatches(region) ? 0.4 : 0.0,
      };
      if (regionWeight <= 0) {
        continue;
      }

      final point = Offset(mesh.vertices[i * 2], mesh.vertices[i * 2 + 1]);
      final verticalDist = (point.dy - hipY).abs();
      if (verticalDist > bandHalf * 1.6) {
        continue;
      }
      final band = 1.0 - (verticalDist / (bandHalf * 1.6)).clamp(0.0, 1.0);
      final bandSmooth = band * band * (3 - 2 * band);

      final t = ((point.dy - shoulderY) / span).clamp(0.0, 1.2);
      // Hip region now starts at t≈0.72; peak a little lower for coverage.
      final profile = ((t - 0.78).abs() < 0.2) ? 1.0 : 0.55;

      final outward = horizontalOutwardFromMidline(
        point: point,
        midlineX: midlineX,
      );
      if (outward == Offset.zero) {
        continue;
      }

      final lateral = ((point.dx - midlineX).abs() /
              (context.imageSize.width * 0.18))
          .clamp(0.0, 1.0);
      final lateralWeight = 0.35 + 0.65 * lateral;

      final w = regionWeight *
          bandSmooth *
          profile *
          lateralWeight *
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
