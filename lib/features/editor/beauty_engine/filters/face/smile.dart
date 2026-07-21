import 'dart:ui';

import '../../warp/models/control_point.dart';
import 'face_warp_context.dart';
import 'face_warp_filter.dart';
import 'face_warp_utils.dart';

/// Sorriso sutil — ≤0.5 só cantos (dentes protegidos).
class SmileFilter extends FaceWarpFilter {
  SmileFilter();

  @override
  String get id => 'smile';

  @override
  String get parameterKey => 'smile';

  @override
  List<String> get affectedRegions => ['lips'];

  static final _smileLowIndices = {
    ...FaceWarpUtils.mouthCornerLeft,
    ...FaceWarpUtils.mouthCornerRight,
  };

  static const _smileHighExtra = {185, 409, 146, 405};

  @override
  List<ControlPoint> buildControlPoints(FaceWarpContext context) {
    final intensity = context.effectiveIntensity;
    if (intensity <= 0) {
      return const [];
    }

    final points = FaceWarpUtils.anchorPoints(context.mesh);
    final lift = context.imageSize.height * 0.018 * intensity;
    final delta = Offset(0, -lift);

    final indices = intensity <= 0.5
        ? _smileLowIndices
        : {..._smileLowIndices, ..._smileHighExtra};

    for (final index in indices) {
      if (FaceWarpUtils.innerMouthExcluded.contains(index)) {
        continue;
      }
      final source = FaceWarpUtils.vertexAt(context.mesh, index);
      if (source == null) {
        continue;
      }
      points.add(ControlPoint(source: source, target: source + delta));
    }

    return points;
  }
}
