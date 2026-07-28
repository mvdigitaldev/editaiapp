import '../../warp/models/control_point.dart';
import 'body_warp_context.dart';

/// Filtro warp corporal — control points a partir da malha pose.
///
/// Caminho legado (MLS). O Body Reshape V2 usa
/// `BodyRegionDeformationStrategy` + `BodyMeshDeformer` sobre malha adaptativa,
/// sem control points.
abstract class BodyWarpFilter {
  String get id;
  String get parameterKey;
  List<String> get affectedRegions;

  /// Índices pose necessários (visibility mínima).
  Set<int> get requiredPoseIndices => const {};

  List<ControlPoint> buildControlPoints(BodyWarpContext context);
}
