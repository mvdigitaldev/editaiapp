import 'dart:ui';

import '../../warp/models/control_point.dart';
import 'face_warp_context.dart';
import 'face_warp_filter.dart';
import 'face_warp_utils.dart';

/// Encolhe queixo — independente de face_slim (subset disjunto de v_face).
class ChinFilter extends FaceWarpFilter {
  ChinFilter();

  @override
  String get id => 'chin';

  @override
  String get parameterKey => 'chin';

  @override
  List<String> get affectedRegions => ['chin'];

  /// Exclui 152 (usado por v_face / jawLeft).
  static const _chinIndices = {175, 199, 200, 18, 313, 421, 428};

  @override
  List<ControlPoint> buildControlPoints(FaceWarpContext context) {
    final intensity = context.effectiveIntensity;
    if (intensity <= 0) {
      return const [];
    }

    final points = FaceWarpUtils.anchorPoints(context.mesh);
    final lift = context.imageSize.height * 0.035 * intensity;
    final narrow = context.imageSize.width * 0.04 * intensity;

    for (final index in _chinIndices) {
      final source = FaceWarpUtils.vertexAt(context.mesh, index);
      if (source == null) {
        continue;
      }
      final towardCenter = context.centerX - source.dx;
      final ratio = towardCenter.abs() / (context.imageSize.width * 0.5);
      points.add(
        ControlPoint(
          source: source,
          target: Offset(
            source.dx + towardCenter.sign * narrow * ratio,
            source.dy - lift,
          ),
        ),
      );
    }

    return points;
  }
}
