import '../../warp/models/control_point.dart';
import 'body_warp_context.dart';
import 'body_warp_filter.dart';

/// Estreita cintura — CPs gerados no pipeline unificado de torso.
///
/// Mantido na lista de filtros para canApply / UI; o compose usa
/// [BodyFilterPipeline] torso unificado para evitar waist+body no mesmo MLS.
/// V2: [WaistStrategy] via [BodyMeshDeformer] / [BodyFilterPipeline.deformAdaptiveMesh].
class WaistSlimFilter extends BodyWarpFilter {
  WaistSlimFilter();

  @override
  String get id => 'waist_slim';

  @override
  String get parameterKey => 'waist_slim';

  @override
  List<String> get affectedRegions => ['waist', 'torso'];

  @override
  Set<int> get requiredPoseIndices => {11, 12, 23, 24};

  @override
  List<ControlPoint> buildControlPoints(BodyWarpContext context) {
    // Pipeline unificado (`_buildUnifiedTorsoSlim`) monta os CPs.
    return const [];
  }
}
