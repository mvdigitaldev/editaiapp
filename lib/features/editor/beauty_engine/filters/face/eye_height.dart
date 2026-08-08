import 'dart:ui';

import '../../models/mesh_region.dart';
import '../../warp/models/control_point.dart';
import 'face_warp_context.dart';
import 'face_warp_filter.dart';
import 'face_warp_utils.dart';

/// Eleva posição vertical dos olhos.
class EyeHeightFilter extends FaceWarpFilter {
  EyeHeightFilter();

  @override
  String get id => 'eye_height';

  @override
  String get parameterKey => 'eye_height';

  @override
  List<String> get affectedRegions => ['left_eye', 'right_eye'];

  @override
  List<ControlPoint> buildControlPoints(FaceWarpContext context) {
    final intensity = context.effectiveIntensity;
    if (intensity <= 0) {
      return const [];
    }

    final lift = context.imageSize.height * 0.018 * intensity;
    final delta = Offset(0, -lift);
    final points = FaceWarpUtils.eyeWarpAnchors(context.mesh);

    for (final region in [MeshRegion.leftEye, MeshRegion.rightEye]) {
      points.addAll(
        FaceWarpUtils.shiftEyeRegion(
          mesh: context.mesh,
          region: region,
          delta: delta,
        ),
      );
    }

    return points;
  }
}
