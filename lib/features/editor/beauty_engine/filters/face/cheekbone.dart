import 'dart:ui';

import '../../models/tri_mesh.dart';
import '../../warp/models/control_point.dart';
import 'face_warp_context.dart';
import 'face_warp_filter.dart';
import 'face_warp_utils.dart';

/// Realça maçãs do rosto — warp sutil + contour overlay (Sprint 14).
class CheekboneFilter extends FaceWarpFilter {
  CheekboneFilter();

  @override
  String get id => 'cheekbone';

  @override
  String get parameterKey => 'cheekbone';

  @override
  List<String> get affectedRegions => ['left_cheek', 'right_cheek'];

  static const _leftZygoma = {123, 147, 187, 116};
  static const _rightZygoma = {352, 411, 425, 345};

  @override
  List<ControlPoint> buildControlPoints(FaceWarpContext context) {
    final intensity = context.effectiveIntensity;
    if (intensity <= 0) {
      return const [];
    }

    final points = FaceWarpUtils.anchorPoints(context.mesh);
    final lift = context.imageSize.height * 0.012 * intensity;
    final outward = context.imageSize.width * 0.018 * intensity;

    for (final index in _leftZygoma) {
      _addCheekbonePoint(
        points: points,
        mesh: context.mesh,
        index: index,
        lift: lift,
        outward: outward,
        isLeft: true,
      );
    }

    for (final index in _rightZygoma) {
      _addCheekbonePoint(
        points: points,
        mesh: context.mesh,
        index: index,
        lift: lift,
        outward: outward,
        isLeft: false,
      );
    }

    return points;
  }

  void _addCheekbonePoint({
    required List<ControlPoint> points,
    required TriMesh mesh,
    required int index,
    required double lift,
    required double outward,
    required bool isLeft,
  }) {
    final source = FaceWarpUtils.vertexAt(mesh, index);
    if (source == null) {
      return;
    }
    final awayFromCenter = isLeft ? -1.0 : 1.0;
    points.add(
      ControlPoint(
        source: source,
        target: Offset(
          source.dx + awayFromCenter * outward,
          source.dy - lift,
        ),
      ),
    );
  }
}
