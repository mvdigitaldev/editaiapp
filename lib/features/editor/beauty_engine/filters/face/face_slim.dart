import 'dart:math' as math;
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
    final maxShift = context.imageSize.width * 0.125 * intensity;
    final centerX = context.centerX;
    final fseProxy = math.min(context.imageSize.width, context.imageSize.height) *
        0.42;

    for (final region in [MeshRegion.jawLeft, MeshRegion.jawRight]) {
      for (final index in FaceWarpUtils.regionIndices(region)) {
        final source = FaceWarpUtils.vertexAt(context.mesh, index);
        if (source == null) {
          continue;
        }
        final towardCenter = centerX - source.dx;
        final lateral = (source.dx - centerX).abs();
        final halfFace = fseProxy * 0.48;
        final edgeWeight = halfFace <= 1e-6
            ? 1.0
            : math.pow((lateral / halfFace).clamp(0.0, 1.0), 0.58).toDouble();
        final shift = towardCenter.sign * maxShift * edgeWeight;
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
