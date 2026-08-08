import 'dart:ui';

import '../../models/mesh_region.dart';
import '../../warp/models/control_point.dart';
import 'face_warp_context.dart';
import 'face_warp_filter.dart';
import 'face_warp_utils.dart';

/// Aumenta ou reduz olhos em torno do centro (protege íris).
class EyeScaleFilter extends FaceWarpFilter {
  EyeScaleFilter();

  @override
  String get id => 'eye_scale';

  @override
  String get parameterKey => 'eye_scale';

  @override
  List<String> get affectedRegions => ['left_eye', 'right_eye'];

  @override
  List<ControlPoint> buildControlPoints(FaceWarpContext context) {
    final intensity = context.effectiveIntensity;
    if (intensity <= 0) {
      return const [];
    }

    final scale = 1 + 0.18 * intensity;
    final points = FaceWarpUtils.eyeWarpAnchors(context.mesh);

    for (final region in [MeshRegion.leftEye, MeshRegion.rightEye]) {
      points.addAll(
        FaceWarpUtils.scaleEyeRegion(
          mesh: context.mesh,
          region: region,
          scale: scale,
        ),
      );
    }

    return points;
  }
}
