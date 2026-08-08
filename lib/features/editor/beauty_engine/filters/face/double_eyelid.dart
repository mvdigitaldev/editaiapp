import 'dart:ui';

import '../../warp/models/control_point.dart';
import 'face_warp_context.dart';
import 'face_warp_filter.dart';
import 'face_warp_utils.dart';

/// Pálpebra dupla — warp sutil na pálpebra superior (overlay via PassEyeOverlay).
class DoubleEyelidFilter extends FaceWarpFilter {
  DoubleEyelidFilter();

  @override
  String get id => 'double_eyelid';

  @override
  String get parameterKey => 'double_eyelid';

  @override
  List<String> get affectedRegions => ['left_eye', 'right_eye'];

  @override
  List<ControlPoint> buildControlPoints(FaceWarpContext context) {
    final intensity = context.effectiveIntensity;
    if (intensity <= 0) {
      return const [];
    }

    final points = FaceWarpUtils.eyeWarpAnchors(context.mesh);
    final foldShift = context.imageSize.height * 0.012 * intensity;

    for (final indices in [
      FaceWarpUtils.upperEyelidLeft,
      FaceWarpUtils.upperEyelidRight,
    ]) {
      for (final index in indices) {
        final source = FaceWarpUtils.vertexAt(context.mesh, index);
        if (source == null) {
          continue;
        }
        points.add(
          ControlPoint(
            source: source,
            target: Offset(source.dx, source.dy + foldShift),
          ),
        );
      }
    }

    return points;
  }
}
