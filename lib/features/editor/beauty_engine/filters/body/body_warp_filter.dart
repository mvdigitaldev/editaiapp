import '../../warp/models/control_point.dart';
import 'body_warp_context.dart';

/// Filtro warp corporal — control points a partir da malha pose.
abstract class BodyWarpFilter {
  String get id;
  String get parameterKey;
  List<String> get affectedRegions;

  /// Índices pose necessários (visibility mínima).
  Set<int> get requiredPoseIndices => const {};

  List<ControlPoint> buildControlPoints(BodyWarpContext context);
}
