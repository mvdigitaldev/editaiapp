import 'dart:ui';

import '../../models/mesh_region.dart';
import '../../warp/models/control_point.dart';
import 'body_warp_context.dart';
import 'body_warp_filter.dart';
import 'body_warp_utils.dart';

/// Estreita cintura (quadril + ombros convergem).
class WaistSlimFilter extends BodyWarpFilter {
  WaistSlimFilter();

  @override
  String get id => 'waist_slim';

  @override
  String get parameterKey => 'waist_slim';

  @override
  List<String> get affectedRegions => ['waist', 'torso'];

  @override
  Set<int> get requiredPoseIndices => {11, 12, 23, 24};

  @override
  List<ControlPoint> buildControlPoints(BodyWarpContext context) {
    final intensity = context.effectiveIntensity;
    if (intensity <= 0) {
      return const [];
    }

    final points = BodyWarpUtils.anchorPoints(context.mesh);
    final maxShift = context.imageSize.width * 0.08 * intensity;

    for (final index in BodyWarpUtils.regionIndices(MeshRegion.waist)) {
      final source = BodyWarpUtils.vertexAt(context.mesh, index);
      if (source == null) {
        continue;
      }
      final towardCenter = context.centerX - source.dx;
      final ratio = towardCenter.abs() / (context.imageSize.width * 0.5);
      points.add(
        ControlPoint(
          source: source,
          target: Offset(
            source.dx + towardCenter.sign * maxShift * ratio,
            source.dy,
          ),
        ),
      );
    }

    return points;
  }
}
