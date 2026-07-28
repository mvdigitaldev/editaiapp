import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../models/body_adjustment.dart';
import '../models/body_joint.dart';
import '../models/body_region.dart';
import 'body_region_deformation_strategy.dart';

/// Afina o pescoço em direção ao eixo cervical.
class NeckStrategy extends BodyRegionDeformationStrategy
    with RegionDeformationMath {
  const NeckStrategy({this.maxShiftFraction = 0.022});

  final double maxShiftFraction;

  @override
  Set<BodyAdjustmentType> get supportedTypes => {
        BodyAdjustmentType.neckSlim,
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
    final nose = context.landmarkPx(BodyJoint.nose);
    if (leftShoulder == null || rightShoulder == null) {
      return;
    }

    final bottom = Offset(
      (leftShoulder.dx + rightShoulder.dx) * 0.5,
      (leftShoulder.dy + rightShoulder.dy) * 0.5,
    );
    final top = nose ??
        Offset(bottom.dx, bottom.dy - context.imageSize.height * 0.12);
    final shiftPx = context.imageSize.width * maxShiftFraction * intensity;
    final halfWidth = context.imageSize.width * 0.055;

    final mesh = context.mesh;
    for (var i = 0; i < mesh.vertexCount; i++) {
      final region = mesh.regionAtVertex(i);
      if (region != BodyRegion.neck &&
          region != BodyRegion.shoulders &&
          !context.regionMatches(region)) {
        continue;
      }
      final regionWeight = region == BodyRegion.neck
          ? 1.0
          : (region == BodyRegion.shoulders ? 0.25 : 0.4);

      final point = Offset(mesh.vertices[i * 2], mesh.vertices[i * 2 + 1]);
      final falloff = falloffAlongAxis(
        point: point,
        a: top,
        b: bottom,
        halfWidth: halfWidth,
      );
      if (falloff <= 0) {
        continue;
      }
      final inward = inwardNormalTowardAxis(point: point, a: top, b: bottom);
      if (inward == Offset.zero) {
        continue;
      }

      // Evita deformar muito perto da cabeça.
      final t = ((point.dy - top.dy) / math.max(bottom.dy - top.dy, 1.0))
          .clamp(0.0, 1.0);
      final profile = 0.35 + 0.65 * t;

      final w = regionWeight *
          falloff *
          profile *
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
}
