import 'dart:ui';

import '../../warp/models/control_point.dart';
import 'face_warp_context.dart';
import 'face_warp_filter.dart';
import 'face_warp_utils.dart';

/// Ajusta dorso — máscara separada dos olhos (landmarks superiores do nariz).
class NoseBridgeFilter extends FaceWarpFilter {
  NoseBridgeFilter();

  @override
  String get id => 'nose_bridge';

  @override
  String get parameterKey => 'nose_bridge';

  @override
  List<String> get affectedRegions => ['nose_bridge'];

  /// Ponte nasal — exclui ponta e laterais baixas.
  static const _bridgeIndices = {168, 6, 197, 195, 5, 4, 45, 275};

  @override
  List<ControlPoint> buildControlPoints(FaceWarpContext context) {
    final intensity = context.effectiveIntensity;
    if (intensity <= 0) {
      return const [];
    }

    final points = FaceWarpUtils.anchorPoints(context.mesh);
    final axis = FaceWarpUtils.noseAxisCenter(context.mesh);
    final slim = context.imageSize.width * 0.025 * intensity;
    final lift = -context.imageSize.height * 0.012 * intensity;

    for (final index in _bridgeIndices) {
      final source = FaceWarpUtils.vertexAt(context.mesh, index);
      if (source == null) {
        continue;
      }
      final towardAxis = axis.dx - source.dx;
      final shiftX = towardAxis.sign * slim * 0.6;
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
