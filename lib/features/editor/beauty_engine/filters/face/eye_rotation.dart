import 'dart:ui';

import '../../models/mesh_region.dart';
import '../../warp/models/control_point.dart';
import 'face_warp_context.dart';
import 'face_warp_filter.dart';
import 'face_warp_utils.dart';

/// Rotação sutil dos cantos externos dos olhos.
class EyeRotationFilter extends FaceWarpFilter {
  EyeRotationFilter();

  @override
  String get id => 'eye_rotation';

  @override
  String get parameterKey => 'eye_rotation';

  @override
  List<String> get affectedRegions => ['left_eye', 'right_eye'];

  @override
  List<ControlPoint> buildControlPoints(FaceWarpContext context) {
    final intensity = context.effectiveIntensity;
    if (intensity <= 0) {
      return const [];
    }

    final angle = 0.08 * intensity;
    final points = FaceWarpUtils.anchorPoints(context.mesh);

    points.addAll(
      FaceWarpUtils.rotateEyeRegion(
        mesh: context.mesh,
        region: MeshRegion.leftEye,
        angleRadians: angle,
      ),
    );
    points.addAll(
      FaceWarpUtils.rotateEyeRegion(
        mesh: context.mesh,
        region: MeshRegion.rightEye,
        angleRadians: context.linkEyes ? -angle : angle,
      ),
    );

    return points;
  }
}
