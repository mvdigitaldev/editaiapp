import 'dart:ui';

import '../../warp/models/control_point.dart';
import 'body_warp_context.dart';
import 'body_warp_filter.dart';
import 'body_warp_utils.dart';

/// Ajusta largura do quadril (landmarks 23/24 + borda estimada).
class HipFilter extends BodyWarpFilter {
  HipFilter();

  @override
  String get id => 'hip';

  @override
  String get parameterKey => 'hip';

  @override
  List<String> get affectedRegions => ['waist'];

  @override
  Set<int> get requiredPoseIndices => {23, 24};

  @override
  List<ControlPoint> buildControlPoints(BodyWarpContext context) {
    final intensity = context.effectiveIntensity;
    if (intensity <= 0) {
      return const [];
    }

    final t = intensity * intensity * (3 - 2 * intensity);
    final a = BodyWarpUtils.vertexAt(context.mesh, 23);
    final b = BodyWarpUtils.vertexAt(context.mesh, 24);
    if (a == null || b == null) {
      return const [];
    }

    // Esquerda/direita na imagem (selfie espelhada inverte labels MediaPipe).
    final imageLeft = a.dx <= b.dx ? a : b;
    final imageRight = a.dx <= b.dx ? b : a;

    final shift = context.imageSize.width * 0.04 * t;
    final pad = context.imageSize.width * 0.03;
    final movable = <ControlPoint>[
      ControlPoint(
        source: BodyWarpUtils.clampToFrame(
          Offset(imageLeft.dx - pad, imageLeft.dy),
          context.imageSize,
        ),
        target: BodyWarpUtils.clampToFrame(
          Offset(imageLeft.dx - pad - shift, imageLeft.dy),
          context.imageSize,
        ),
      ),
      ControlPoint(
        source: BodyWarpUtils.clampToFrame(
          Offset(imageRight.dx + pad, imageRight.dy),
          context.imageSize,
        ),
        target: BodyWarpUtils.clampToFrame(
          Offset(imageRight.dx + pad + shift, imageRight.dy),
          context.imageSize,
        ),
      ),
      ControlPoint(
        source: Offset((imageLeft.dx + imageRight.dx) * 0.5, imageLeft.dy),
        target: Offset((imageLeft.dx + imageRight.dx) * 0.5, imageLeft.dy),
      ),
    ];

    return [
      ...BodyWarpUtils.anchorPoints(
        context.mesh,
        excludeIndices: {23, 24},
      ),
      ...movable,
      ...BodyWarpUtils.backgroundFreezeRing(
        movable: movable,
        imageSize: context.imageSize,
      ),
    ];
  }
}
