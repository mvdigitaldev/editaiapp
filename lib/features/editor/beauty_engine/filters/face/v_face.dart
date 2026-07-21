import 'dart:ui';

import '../../models/mesh_region.dart';
import '../../warp/models/control_point.dart';
import 'face_warp_context.dart';
import 'face_warp_filter.dart';
import 'face_warp_utils.dart';

/// Formato V — mandíbula mais estreita + queixo levemente elevado.
class VFaceFilter extends FaceWarpFilter {
  VFaceFilter();

  @override
  String get id => 'v_face';

  @override
  String get parameterKey => 'v_face';

  @override
  List<String> get affectedRegions => ['jaw', 'chin'];

  static const _chinIndices = {152, 175, 199, 200, 18, 313, 421, 428};

  @override
  List<ControlPoint> buildControlPoints(FaceWarpContext context) {
    final intensity = context.effectiveIntensity;
    if (intensity <= 0) {
      return const [];
    }

    final points = FaceWarpUtils.anchorPoints(context.mesh);
    final jawShift = context.imageSize.width * 0.14 * intensity;
    final chinLift = context.imageSize.height * 0.025 * intensity;

    for (final region in [MeshRegion.jawLeft, MeshRegion.jawRight]) {
      for (final index in FaceWarpUtils.regionIndices(region)) {
        final source = FaceWarpUtils.vertexAt(context.mesh, index);
        if (source == null) {
          continue;
        }
        final towardCenter = context.centerX - source.dx;
        final ratio = towardCenter.abs() / (context.imageSize.width * 0.5);
        final shiftX = towardCenter.sign * jawShift * ratio;
        points.add(
          ControlPoint(
            source: source,
            target: Offset(source.dx + shiftX, source.dy - chinLift * 0.3),
          ),
        );
      }
    }

    for (final index in _chinIndices) {
      final source = FaceWarpUtils.vertexAt(context.mesh, index);
      if (source == null) {
        continue;
      }
      points.add(
        ControlPoint(
          source: source,
          target: Offset(source.dx, source.dy - chinLift),
        ),
      );
    }

    return points;
  }
}
