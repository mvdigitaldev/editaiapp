import 'dart:ui';

import '../../warp/models/control_point.dart';
import 'face_warp_context.dart';
import 'face_warp_filter.dart';
import 'face_warp_utils.dart';

/// Encolhe/eleva queixo — pivot na ponta (152) com lábio estabilizado.
class ChinFilter extends FaceWarpFilter {
  ChinFilter();

  @override
  String get id => 'chin';

  @override
  String get parameterKey => 'chin';

  @override
  List<String> get affectedRegions => ['chin'];

  static const _chinIndices = {152, 175, 199, 200, 18, 313, 421, 428};

  @override
  List<ControlPoint> buildControlPoints(FaceWarpContext context) {
    final intensity = context.effectiveIntensity;
    if (intensity <= 0) {
      return const [];
    }

    final points = [
      ...FaceWarpUtils.anchorPoints(context.mesh),
      ...FaceWarpUtils.lipStabilizerPoints(context.mesh),
    ];
    final lift = context.imageSize.height * 0.035 * intensity;
    final narrow = context.imageSize.width * 0.04 * intensity;
    final centerX = context.centerX;
    final chinPivot = FaceWarpUtils.landmarkPoint(context.face, 152, context.imageSize) ??
        context.faceCenter;
    final halfFace = (context.imageSize.width * 0.5).clamp(1.0, double.infinity);

    for (final index in _chinIndices) {
      final source = FaceWarpUtils.vertexAt(context.mesh, index);
      if (source == null) {
        continue;
      }
      final towardCenter = centerX - source.dx;
      final distFromPivot = (source.dy - chinPivot.dy).abs();
      final narrowFactor = (distFromPivot / (context.imageSize.height * 0.08))
          .clamp(0.35, 1.0);
      final ratio = (towardCenter.abs() / halfFace).clamp(0.2, 1.0);
      points.add(
        ControlPoint(
          source: source,
          target: Offset(
            source.dx + towardCenter.sign * narrow * ratio * narrowFactor,
            source.dy - lift * narrowFactor,
          ),
        ),
      );
    }

    return points;
  }
}
