import 'dart:ui';

import '../../warp/models/control_point.dart';
import 'face_warp_context.dart';
import 'face_warp_filter.dart';
import 'face_warp_utils.dart';

/// Alonga ou encurta nariz verticalmente.
class NoseLengthFilter extends FaceWarpFilter {
  NoseLengthFilter();

  @override
  String get id => 'nose_length';

  @override
  String get parameterKey => 'nose_length';

  @override
  List<String> get affectedRegions => ['nose'];

  static const _indices = {1, 2, 4, 5, 19, 94, 98, 97, 326, 327, 294, 278};

  @override
  List<ControlPoint> buildControlPoints(FaceWarpContext context) {
    final intensity = context.effectiveIntensity;
    if (intensity <= 0) {
      return const [];
    }

    final points = FaceWarpUtils.anchorPoints(context.mesh);
    final shiftY = context.imageSize.height * 0.04 * intensity;

    for (final index in _indices) {
      final source = FaceWarpUtils.vertexAt(context.mesh, index);
      if (source == null) {
        continue;
      }
      points.add(
        ControlPoint(
          source: source,
          target: Offset(source.dx, source.dy + shiftY),
        ),
      );
    }

    return points;
  }
}
