import 'dart:ui';

import '../../models/mesh_region.dart';
import '../../warp/models/control_point.dart';
import 'face_warp_context.dart';
import 'face_warp_filter.dart';
import 'face_warp_utils.dart';

/// Emagrece mandíbula (ambos os lados).
class FaceSlimFilter extends FaceWarpFilter {
  FaceSlimFilter();

  @override
  String get id => 'face_slim';

  @override
  String get parameterKey => 'face_slim';

  @override
  List<String> get affectedRegions => ['jaw_left', 'jaw_right'];

  @override
  List<ControlPoint> buildControlPoints(FaceWarpContext context) {
    final intensity = context.effectiveIntensity;
    if (intensity <= 0) {
      return const [];
    }

    final points = FaceWarpUtils.anchorPoints(context.mesh);
    final maxShift = context.imageSize.width * 0.12 * intensity;

    for (final region in [MeshRegion.jawLeft, MeshRegion.jawRight]) {
      for (final index in FaceWarpUtils.regionIndices(region)) {
        final source = FaceWarpUtils.vertexAt(context.mesh, index);
        if (source == null) {
          continue;
        }
        final towardCenter = context.centerX - source.dx;
        final ratio = towardCenter.abs() / (context.imageSize.width * 0.5);
        final shift = towardCenter.sign * maxShift * ratio;
        points.add(
          ControlPoint(
            source: source,
            target: Offset(source.dx + shift, source.dy),
          ),
        );
      }
    }

    return points;
  }
}
