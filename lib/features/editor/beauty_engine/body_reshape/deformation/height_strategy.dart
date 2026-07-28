import 'dart:typed_data';
import 'dart:ui';

import '../models/body_adjustment.dart';
import '../models/body_joint.dart';
import '../models/body_region.dart';
import 'body_region_deformation_strategy.dart';

/// Alonga altura corporal e/ou pernas (estiramento vertical a partir do quadril).
class HeightStrategy extends BodyRegionDeformationStrategy
    with RegionDeformationMath {
  const HeightStrategy({
    this.heightStretchFraction = 0.045,
    this.legStretchFraction = 0.06,
  });

  final double heightStretchFraction;
  final double legStretchFraction;

  @override
  Set<BodyAdjustmentType> get supportedTypes => {
        BodyAdjustmentType.height,
        BodyAdjustmentType.legLength,
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
    final leftAnkle = context.landmarkPx(BodyJoint.leftAnkle);
    final rightAnkle = context.landmarkPx(BodyJoint.rightAnkle);
    if (leftHip == null || rightHip == null) {
      return;
    }

    final hipY = (leftHip.dy + rightHip.dy) * 0.5;
    final ankleY = leftAnkle != null && rightAnkle != null
        ? (leftAnkle.dy + rightAnkle.dy) * 0.5
        : context.imageSize.height * 0.92;
    final isFullHeight = context.adjustment.type == BodyAdjustmentType.height;
    final stretchPx = context.imageSize.height *
        (isFullHeight ? heightStretchFraction : legStretchFraction) *
        intensity;
    final maxY = context.imageSize.height * 0.98;

    final mesh = context.mesh;
    for (var i = 0; i < mesh.vertexCount; i++) {
      final region = mesh.regionAtVertex(i);
      final regionWeight = _regionWeight(region, isFullHeight: isFullHeight);
      if (regionWeight <= 0 && !context.regionMatches(region)) {
        continue;
      }
      final weight = regionWeight > 0
          ? regionWeight
          : (context.regionMatches(region) ? 0.4 : 0.0);
      if (weight <= 0) {
        continue;
      }

      final point = Offset(mesh.vertices[i * 2], mesh.vertices[i * 2 + 1]);
      if (isFullHeight) {
        // Escala vertical a partir dos tornozelos (pés fixos).
        final t = ((point.dy - ankleY) / (hipY - ankleY + 1e-6)).clamp(0.0, 2.0);
        // Acima do tornozelo sobe; peito/cabeça sobem mais.
        final lift = stretchPx * t.clamp(0.0, 1.4) * 0.85;
        if (lift.abs() < 1e-4) {
          continue;
        }
        final targetY = (point.dy - lift).clamp(0.0, maxY);
        accumulateDelta(
          deltas,
          i,
          0,
          targetY - point.dy,
          weight * mesh.weights[i].clamp(0.0, 1.0),
        );
      } else {
        // Alongar pernas: só abaixo do quadril.
        if (point.dy < hipY - 4) {
          continue;
        }
        final t = ((point.dy - hipY) / (ankleY - hipY + 1e-6)).clamp(0.0, 1.2);
        final lift = stretchPx * t;
        final targetY = (point.dy + lift).clamp(point.dy, maxY);
        accumulateDelta(
          deltas,
          i,
          0,
          targetY - point.dy,
          weight * mesh.weights[i].clamp(0.0, 1.0),
        );
      }
    }
  }

  double _regionWeight(BodyRegion region, {required bool isFullHeight}) {
    if (isFullHeight) {
      return switch (region) {
        BodyRegion.torso ||
        BodyRegion.chest ||
        BodyRegion.waist ||
        BodyRegion.shoulders ||
        BodyRegion.neck =>
          1.0,
        BodyRegion.hip || BodyRegion.butt => 0.7,
        BodyRegion.leftThigh ||
        BodyRegion.rightThigh ||
        BodyRegion.leftCalf ||
        BodyRegion.rightCalf =>
          0.35,
        _ => 0.0,
      };
    }
    return switch (region) {
      BodyRegion.leftThigh || BodyRegion.rightThigh => 1.0,
      BodyRegion.leftCalf || BodyRegion.rightCalf => 1.0,
      BodyRegion.hip || BodyRegion.butt => 0.25,
      _ => 0.0,
    };
  }
}
