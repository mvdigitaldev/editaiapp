import '../../warp/models/control_point.dart';
import 'body_warp_context.dart';
import 'body_warp_filter.dart';

/// Emagrece torso — CPs gerados no pipeline unificado de torso.
///
/// Mantido na lista de filtros para canApply / UI; o compose usa
/// [BodyFilterPipeline] torso unificado para evitar waist+body no mesmo MLS.
class BodySlimFilter extends BodyWarpFilter {
  BodySlimFilter();

  @override
  String get id => 'body_slim';

  @override
  String get parameterKey => 'body_slim';

  @override
  List<String> get affectedRegions => ['torso'];

  @override
  Set<int> get requiredPoseIndices => {11, 12, 23, 24};

  @override
  List<ControlPoint> buildControlPoints(BodyWarpContext context) {
    // Pipeline unificado (`_buildUnifiedTorsoSlim`) monta os CPs.
    return const [];
  }
}
