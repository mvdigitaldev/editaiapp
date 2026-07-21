import 'dart:ui';

import '../../warp/models/control_point.dart';
import 'face_warp_context.dart';
import 'face_warp_filter.dart';
import 'face_warp_utils.dart';

/// Aumenta largura da boca (cantos laterais).
class MouthWidthFilter extends FaceWarpFilter {
  MouthWidthFilter();

  @override
  String get id => 'mouth_width';

  @override
  String get parameterKey => 'mouth_width';

  @override
  List<String> get affectedRegions => ['lips'];

  @override
  List<ControlPoint> buildControlPoints(FaceWarpContext context) {
    final intensity = context.effectiveIntensity;
    if (intensity <= 0) {
      return const [];
    }

    final points = FaceWarpUtils.anchorPoints(context.mesh);
    final shift = context.imageSize.width * 0.022 * intensity;

    points.addAll(
      FaceWarpUtils.shiftLipIndices(
        mesh: context.mesh,
        indices: FaceWarpUtils.mouthCornerLeft,
        delta: Offset(-shift, 0),
      ),
    );
    points.addAll(
      FaceWarpUtils.shiftLipIndices(
        mesh: context.mesh,
        indices: FaceWarpUtils.mouthCornerRight,
        delta: Offset(shift, 0),
      ),
    );

    return points;
  }
}
