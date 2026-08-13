import '../filters/face/face_filter_pipeline.dart';
import '../models/tri_mesh.dart';
import 'anatomy/anatomical_constraint_engine.dart';
import 'anatomy/anatomical_intent.dart';
import 'anatomy/anatomical_intent_factory.dart';
import 'anatomy/constrained_vertex_field.dart';
import 'anatomy/face_mesh_deformation_engine.dart';
import 'face_warp_mvp_operations.dart';
import 'face_warp_operation.dart';

/// Orquestrador genérico do Face Warp Engine (Fase 15).
///
/// Fluxo de uma operação:
/// ```
/// parameters → intents → ACE → structural pipeline → ConstrainedVertexField
///                                                      ↓
///                                              renderer (PassWarp)
/// ```
abstract final class FaceWarpEngine {
  FaceWarpEngine._();

  /// Operações MVP registradas.
  static List<FaceWarpOperation> get mvpOperations =>
      FaceWarpMvpOperations.all;

  /// Composição completa: ACE + Phase 9 + Safety Gate.
  ///
  /// Retorna campo zero quando nenhuma ferramenta warp está ativa.
  static ConstrainedVertexField composeVertexField({
    required Map<String, double> parameters,
    required FaceAnatomyContext context,
    required TriMesh mesh,
    AnatomicalConstraintEngine? ace,
    bool structuralPipelineEnabled = true,
  }) {
    if (!const FaceFilterPipeline().hasActiveWarp(parameters)) {
      return ConstrainedVertexField.zero();
    }

    final engine = FaceMeshDeformationEngine(
      ace: ace ?? const AnatomicalConstraintEngine(),
    );
    return engine.composeVertexField(
      parameters: parameters,
      context: context,
      mesh: mesh,
      applyStructuralPipeline: structuralPipelineEnabled,
    );
  }

  /// Intents ativos (para diagnóstico / métricas).
  static List<AnatomicalIntent> activeIntents({
    required Map<String, double> parameters,
    required FaceAnatomyContext context,
  }) =>
      AnatomicalIntentFactory.build(
        parameters: parameters,
        context: context,
      );
}
