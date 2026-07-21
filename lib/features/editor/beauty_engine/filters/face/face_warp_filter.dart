import '../../models/filter_context.dart';
import '../beauty_filter.dart';
import '../../warp/models/control_point.dart';
import 'face_warp_context.dart';

/// Filtro warp facial — constrói control points MLS.
abstract class FaceWarpFilter implements BeautyFilter {
  /// Chave snake_case em `ProcessingPipeline.effectiveParameters`.
  String get parameterKey;

  /// Regiões afetadas (documentação / máscaras futuras).
  List<String> get affectedRegions;

  List<ControlPoint> buildControlPoints(FaceWarpContext context);

  @override
  void apply(FilterContext context) {
    // Composição feita via [FaceFilterPipeline] no controller.
  }
}
