import 'dart:ui';

import '../../models/mesh_region.dart';
import '../../warp/models/control_point.dart';
import 'face_warp_context.dart';
import 'face_warp_filter.dart';
import 'face_warp_utils.dart';

/// Aumenta distância entre os olhos (afasta lateralmente).
class EyeDistanceFilter extends FaceWarpFilter {
  EyeDistanceFilter();

  @override
  String get id => 'eye_distance';

  @override
  String get parameterKey => 'eye_distance';

  @override
  List<String> get affectedRegions => ['left_eye', 'right_eye'];

  @override
  List<ControlPoint> buildControlPoints(FaceWarpContext context) {
    final intensity = context.effectiveIntensity;
    if (intensity <= 0) {
      return const [];
    }

    final shift = context.imageSize.width * 0.025 * intensity;
    final points = FaceWarpUtils.anchorPoints(context.mesh);

    points.addAll(
      FaceWarpUtils.shiftEyeRegion(
        mesh: context.mesh,
        region: MeshRegion.leftEye,
        delta: Offset(-shift, 0),
      ),
    );
    points.addAll(
      FaceWarpUtils.shiftEyeRegion(
        mesh: context.mesh,
        region: MeshRegion.rightEye,
        delta: Offset(shift, 0),
      ),
    );

    return points;
  }
}
