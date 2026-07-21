import 'dart:ui';

import '../../warp/models/control_point.dart';
import 'face_warp_context.dart';
import 'face_warp_filter.dart';
import 'face_warp_utils.dart';

/// Aumenta espessura dos lábios (exterior only).
class LipThicknessFilter extends FaceWarpFilter {
  LipThicknessFilter();

  @override
  String get id => 'lip_thickness';

  @override
  String get parameterKey => 'lip_thickness';

  @override
  List<String> get affectedRegions => ['lips'];

  @override
  List<ControlPoint> buildControlPoints(FaceWarpContext context) {
    final intensity = context.effectiveIntensity;
    if (intensity <= 0) {
      return const [];
    }

    final center = FaceWarpUtils.lipCenter(context.mesh);
    if (center == null) {
      return const [];
    }

    final points = FaceWarpUtils.anchorPoints(context.mesh);
    final expand = context.imageSize.height * 0.014 * intensity;

    for (final index in FaceWarpUtils.lipOuterUpper) {
      if (FaceWarpUtils.innerMouthExcluded.contains(index)) {
        continue;
      }
      final source = FaceWarpUtils.vertexAt(context.mesh, index);
      if (source == null) {
        continue;
      }
      points.add(
        ControlPoint(
          source: source,
          target: Offset(source.dx, source.dy - expand),
        ),
      );
    }

    for (final index in FaceWarpUtils.lipOuterLower) {
      if (FaceWarpUtils.innerMouthExcluded.contains(index)) {
        continue;
      }
      final source = FaceWarpUtils.vertexAt(context.mesh, index);
      if (source == null) {
        continue;
      }
      points.add(
        ControlPoint(
          source: source,
          target: Offset(source.dx, source.dy + expand),
        ),
      );
    }

    return points;
  }
}
