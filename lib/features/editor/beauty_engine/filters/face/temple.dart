import 'dart:ui';

import '../../warp/models/control_point.dart';
import 'face_warp_context.dart';
import 'face_warp_filter.dart';
import 'face_warp_utils.dart';

/// Estreita têmporas lateralmente (Sprint 15).
class TempleFilter extends FaceWarpFilter {
  TempleFilter();

  @override
  String get id => 'temple';

  @override
  String get parameterKey => 'temple';

  @override
  List<String> get affectedRegions => ['temple'];

  static const _templeLeft = {234, 127, 162, 93, 21};
  static const _templeRight = {251, 284, 356, 389, 297};

  @override
  List<ControlPoint> buildControlPoints(FaceWarpContext context) {
    final intensity = context.effectiveIntensity;
    if (intensity <= 0) {
      return const [];
    }

    final points = FaceWarpUtils.anchorPoints(context.mesh);
    final maxShift = context.imageSize.width * 0.06 * intensity;

    for (final index in _templeLeft) {
      final source = FaceWarpUtils.vertexAt(context.mesh, index);
      if (source == null) {
        continue;
      }
      points.add(
        ControlPoint(
          source: source,
          target: Offset(source.dx + maxShift, source.dy),
        ),
      );
    }

    for (final index in _templeRight) {
      final source = FaceWarpUtils.vertexAt(context.mesh, index);
      if (source == null) {
        continue;
      }
      points.add(
        ControlPoint(
          source: source,
          target: Offset(source.dx - maxShift, source.dy),
        ),
      );
    }

    return points;
  }
}
