import 'dart:ui';

import '../../warp/models/control_point.dart';
import 'face_warp_context.dart';
import 'face_warp_filter.dart';
import 'face_warp_utils.dart';

/// Ajusta ponta do nariz (vertical + leve slim).
class NoseTipFilter extends FaceWarpFilter {
  NoseTipFilter();

  @override
  String get id => 'nose_tip';

  @override
  String get parameterKey => 'nose_tip';

  @override
  List<String> get affectedRegions => ['nose_tip'];

  static const _tipIndices = {1, 2, 98, 97, 326, 327, 4, 5, 19};

  @override
  List<ControlPoint> buildControlPoints(FaceWarpContext context) {
    final intensity = context.effectiveIntensity;
    if (intensity <= 0) {
      return const [];
    }

    final points = FaceWarpUtils.anchorPoints(context.mesh);
    final axis = FaceWarpUtils.noseAxisCenter(context.mesh);
    final lift = -context.imageSize.height * 0.02 * intensity;
    final slim = context.imageSize.width * 0.02 * intensity;

    for (final index in _tipIndices) {
      final source = FaceWarpUtils.vertexAt(context.mesh, index);
      if (source == null) {
        continue;
      }
      final towardAxis = axis.dx - source.dx;
      final shiftX = towardAxis.sign * slim * 0.5;
      points.add(
        ControlPoint(
          source: source,
          target: Offset(source.dx + shiftX, source.dy + lift),
        ),
      );
    }

    return points;
  }
}
