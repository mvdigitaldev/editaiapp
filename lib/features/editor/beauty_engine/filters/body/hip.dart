import 'dart:ui';

import '../../warp/models/control_point.dart';
import 'body_warp_context.dart';
import 'body_warp_filter.dart';
import 'body_warp_utils.dart';

/// Ajusta largura do quadril (landmarks 23/24).
class HipFilter extends BodyWarpFilter {
  HipFilter();

  @override
  String get id => 'hip';

  @override
  String get parameterKey => 'hip';

  @override
  List<String> get affectedRegions => ['waist'];

  @override
  Set<int> get requiredPoseIndices => {23, 24};

  @override
  List<ControlPoint> buildControlPoints(BodyWarpContext context) {
    final intensity = context.effectiveIntensity;
    if (intensity <= 0) {
      return const [];
    }

    final points = BodyWarpUtils.anchorPoints(context.mesh);
    final shift = context.imageSize.width * 0.035 * intensity;

    for (final index in [23, 24]) {
      final source = BodyWarpUtils.vertexAt(context.mesh, index);
      if (source == null) {
        continue;
      }
      final away = index == 23 ? -1.0 : 1.0;
      points.add(
        ControlPoint(
          source: source,
          target: Offset(source.dx + away * shift, source.dy),
        ),
      );
    }

    return points;
  }
}
