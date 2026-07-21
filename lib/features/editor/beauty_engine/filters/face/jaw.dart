import 'dart:ui';

import '../../warp/models/control_point.dart';
import 'face_warp_context.dart';
import 'face_warp_filter.dart';
import 'face_warp_utils.dart';

/// Define mandíbula inferior — índices disjuntos de face_slim / v_face (Sprint 13).
class JawFilter extends FaceWarpFilter {
  JawFilter();

  @override
  String get id => 'jaw';

  @override
  String get parameterKey => 'jaw';

  @override
  List<String> get affectedRegions => ['jaw'];

  /// Contorno lateral inferior — não sobrepõe MeshRegion.jawLeft/jawRight.
  static const _jawLeft = {234, 127, 162, 93};
  static const _jawRight = {356, 389, 251, 284};

  @override
  List<ControlPoint> buildControlPoints(FaceWarpContext context) {
    final intensity = context.effectiveIntensity;
    if (intensity <= 0) {
      return const [];
    }

    final points = FaceWarpUtils.anchorPoints(context.mesh);
    final maxShift = context.imageSize.width * 0.09 * intensity;

    for (final index in _jawLeft) {
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
            source.dx + towardCenter.sign * maxShift * ratio,
            source.dy,
          ),
        ),
      );
    }

    for (final index in _jawRight) {
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
            source.dx + towardCenter.sign * maxShift * ratio,
            source.dy,
          ),
        ),
      );
    }

    return points;
  }
}
