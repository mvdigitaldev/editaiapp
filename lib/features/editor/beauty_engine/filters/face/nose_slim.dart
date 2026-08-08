import 'dart:ui';

import '../../warp/models/control_point.dart';
import 'face_warp_context.dart';
import 'face_warp_filter.dart';
import 'face_warp_utils.dart';

/// Estreita nariz lateralmente (mantém eixo central).
class NoseSlimFilter extends FaceWarpFilter {
  NoseSlimFilter();

  @override
  String get id => 'nose_slim';

  @override
  String get parameterKey => 'nose_slim';

  @override
  List<String> get affectedRegions => ['nose'];

  /// Landmarks laterais do nariz (compartilhado com V3 pilot).
  static const lateralIndices = {
    48, 64, 115, 220, 45, 275, 440, 344, 278, 294, 327, 326,
    49, 131, 134, 51, 3, 195, 197, 419, 248, 456,
  };

  @override
  List<ControlPoint> buildControlPoints(FaceWarpContext context) {
    final intensity = context.effectiveIntensity;
    if (intensity <= 0) {
      return const [];
    }

    final points = [
      ...FaceWarpUtils.mouthStabilizerPoints(context.mesh),
      ...FaceWarpUtils.anchorPoints(context.mesh),
    ];
    final axis = FaceWarpUtils.noseAxisCenter(context.mesh);
    final maxShift = context.imageSize.width * 0.045 * intensity;

    for (final index in lateralIndices) {
      final source = FaceWarpUtils.vertexAt(context.mesh, index);
      if (source == null) {
        continue;
      }
      final towardAxis = axis.dx - source.dx;
      final shift = towardAxis.sign * maxShift * (towardAxis.abs() / context.imageSize.width).clamp(0.2, 1.0);
      points.add(
        ControlPoint(
          source: source,
          target: Offset(source.dx + shift, source.dy),
        ),
      );
    }

    return points;
  }
}
