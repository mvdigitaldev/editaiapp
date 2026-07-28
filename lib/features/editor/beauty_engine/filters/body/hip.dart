import '../../warp/models/control_point.dart';
import 'body_warp_context.dart';
import 'body_warp_filter.dart';
import 'body_warp_utils.dart';

/// Ajusta largura do quadril (landmarks 23/24 + borda real da silhueta).
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

    // Positivo = alargar (para fora).
    final shift = context.imageSize.width * 0.04 * t;
    final movable = BodyWarpUtils.hipSidePoints(
      landmarkA: a,
      landmarkB: b,
      imageSize: context.imageSize,
      shiftPx: shift,
      personMask: context.personMask,
    );

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
