import 'dart:ui';

import '../../warp/models/control_point.dart';
import 'body_warp_context.dart';
import 'body_warp_filter.dart';
import 'body_warp_utils.dart';

/// Estreita pescoço (nariz → ombros).
class NeckSlimFilter extends BodyWarpFilter {
  NeckSlimFilter();

  @override
  String get id => 'neck_slim';

  @override
  String get parameterKey => 'neck_slim';

  @override
  List<String> get affectedRegions => ['neck'];

  @override
  Set<int> get requiredPoseIndices => {0, 11, 12};

  @override
  List<ControlPoint> buildControlPoints(BodyWarpContext context) {
    final intensity = context.effectiveIntensity;
    if (intensity <= 0) {
      return const [];
    }

    final points = BodyWarpUtils.anchorPoints(context.mesh);
    final maxShift = context.imageSize.width * 0.025 * intensity;

    for (final index in [0, 11, 12]) {
      final source = BodyWarpUtils.vertexAt(context.mesh, index);
      if (source == null) {
        continue;
      }
      if (index == 0) {
        continue;
      }
      final towardCenter = context.centerX - source.dx;
      points.add(
        ControlPoint(
          source: source,
          target: Offset(
            source.dx + towardCenter.sign * maxShift,
            source.dy,
          ),
        ),
      );
    }

    return points;
  }
}
