import 'dart:ui';

import '../../models/mesh_region.dart';
import '../../warp/models/control_point.dart';
import 'face_warp_context.dart';
import 'face_warp_filter.dart';
import 'face_warp_utils.dart';

/// Escala cabeça via malha facial — não usa body mesh (Sprint 20).
class HeadSizeFilter extends FaceWarpFilter {
  HeadSizeFilter();

  @override
  String get id => 'head_size';

  @override
  String get parameterKey => 'head_size';

  @override
  List<String> get affectedRegions => ['face_oval'];

  @override
  List<ControlPoint> buildControlPoints(FaceWarpContext context) {
    final intensity = context.effectiveIntensity;
    if (intensity <= 0) {
      return const [];
    }

    final center = FaceWarpUtils.faceOvalCenter(context.face, context.imageSize) ??
        FaceWarpUtils.faceCenter(context.face, context.imageSize);
    if (center == null) {
      return const [];
    }

    final scale = 1 - 0.1 * intensity;
    final points = FaceWarpUtils.anchorPoints(context.mesh);

    for (final index in FaceWarpUtils.regionIndices(MeshRegion.faceOval)) {
      if (FaceWarpUtils.isIrisLandmark(index)) {
        continue;
      }
      final source = FaceWarpUtils.vertexAt(context.mesh, index);
      if (source == null) {
        continue;
      }
      final dx = source.dx - center.dx;
      final dy = source.dy - center.dy;
      points.add(
        ControlPoint(
          source: source,
          target: Offset(center.dx + dx * scale, center.dy + dy * scale),
        ),
      );
    }

    return points;
  }
}
