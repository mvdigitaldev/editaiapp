import 'dart:ui';

import '../../models/mesh_region.dart';
import '../../warp/models/control_point.dart';
import 'face_warp_context.dart';
import 'face_warp_filter.dart';
import 'face_warp_utils.dart';

/// Estreita bochechas horizontalmente.
class NarrowFaceFilter extends FaceWarpFilter {
  NarrowFaceFilter();

  @override
  String get id => 'narrow_face';

  @override
  String get parameterKey => 'narrow_face';

  @override
  List<String> get affectedRegions => ['left_cheek', 'right_cheek'];

  @override
  List<ControlPoint> buildControlPoints(FaceWarpContext context) {
    final intensity = context.effectiveIntensity;
    if (intensity <= 0) {
      return const [];
    }

    final points = FaceWarpUtils.anchorPoints(context.mesh);
    final maxShift = context.imageSize.width * 0.08 * intensity;

    for (final region in [MeshRegion.leftCheek, MeshRegion.rightCheek]) {
      for (final index in FaceWarpUtils.regionIndices(region)) {
        final source = FaceWarpUtils.vertexAt(context.mesh, index);
        if (source == null) {
          continue;
        }
        final towardCenter = context.centerX - source.dx;
        final shift = towardCenter.sign * maxShift * 0.85;
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
