import 'dart:math' as math;
import 'dart:ui';

import '../../config/face_warp_v3_config.dart';
import '../../filters/face/face_filter_pipeline.dart';
import '../../filters/face/face_warp_utils.dart';
import '../../mesh/mesh_topology.dart';
import '../../models/face_mesh_result.dart';
import '../../models/mesh_region.dart';
import '../../models/tri_mesh.dart';
import '../../models/warp_field.dart';
import '../../segment/person_mask.dart';
import '../../warp/warp_field_builder.dart';
import 'anatomical_constraint_engine.dart';
import 'anatomical_intent.dart';
import 'anatomical_intent_factory.dart';
import 'constrained_vertex_field.dart';
import 'face_warp_debug_stats.dart';
import 'face_warp_vacancy_fill.dart';
import 'face_matte_roi.dart';
import '../face_warp_structural_pipeline.dart';
import '../face_mesh_gpu_payload.dart';
import '../face_mesh_warp_rasterizer.dart';

/// Orquestra intents → ACE → rasterizer malha (V3).
class FaceMeshDeformationEngine {
  const FaceMeshDeformationEngine({
    this.ace = const AnatomicalConstraintEngine(),
  });

  final AnatomicalConstraintEngine ace;

  static const _minVertexDisplacementPx = 0.05;

  ConstrainedVertexField composeVertexField({
    required Map<String, double> parameters,
    required FaceAnatomyContext context,
    TriMesh? mesh,
    bool applyStructuralPipeline = true,
  }) {
    final intents = AnatomicalIntentFactory.build(
      parameters: parameters,
      context: context,
    );
    if (intents.isEmpty) {
      return ConstrainedVertexField.zero();
    }
    final rawField = ace.compose(intents: intents, context: context);

    if (mesh == null ||
        !applyStructuralPipeline ||
        !FaceWarpV3Config.enabled ||
        !FaceWarpV3Config.useMeshWarpV3) {
      return rawField;
    }

    return FaceWarpStructuralPipeline.apply(
      mesh: mesh,
      inputField: rawField,
    ).vertexField;
  }

  WarpField? composeWarpField({
    required FaceMeshResult face,
    required TriMesh mesh,
    required Size imageSize,
    required Map<String, double> parameters,
    double intensityScale = 1.0,
    bool linkEyes = true,
    bool interactivePreview = false,
    bool exporting = false,
    PersonMask? personMask,
  }) {
    if (!const FaceFilterPipeline().hasActiveWarp(parameters)) {
      return null;
    }

    final context = FaceAnatomyContext(
      face: face,
      imageSize: imageSize,
      mesh: mesh,
      intensityScale: intensityScale,
      linkEyes: linkEyes,
    );

    final vertexField = composeVertexField(
      parameters: parameters,
      context: context,
      mesh: mesh,
    );

    if (vertexField.maxDisplacementMagnitude() <= _minVertexDisplacementPx) {
      return null;
    }

    // Malha direta (AAM) — preview e export; evita spread/heurística de grade.
    final gpuPiecewise = FaceWarpV3Config.useGpuPiecewiseAffine;
    final directMesh = FaceWarpV3Config.useDirectMeshRender || gpuPiecewise;

    final mvpMeshPath = FaceWarpVacancyFill.usesMvpMeshPath(parameters);
    final builder = interactivePreview && !exporting
        ? (mvpMeshPath
            ? WarpFieldBuilder.forFaceSlimInteractive(imageSize)
            : WarpFieldBuilder.forFaceMeshV3Interactive(imageSize))
        : directMesh
            ? WarpFieldBuilder.forFaceMeshV3Direct(imageSize, exporting: exporting)
            : WarpFieldBuilder.forFaceWarp(imageSize, exporting: exporting);

    final matte = FaceMatteRoi.buildInfluenceMap(
      face: face,
      imageSize: imageSize,
      personMask: personMask,
      lateralRadiusExpand: mvpMeshPath ? 0.07 : 0.0,
    );

    final intensity = _peakIntensity(parameters);

    final field = FaceMeshWarpRasterizer.rasterizeFromVertexField(
      sourceMesh: mesh,
      vertexField: vertexField,
      imageSize: imageSize,
      region: MeshRegion.faceOval,
      gridWidth: builder.gridWidth,
      gridHeight: builder.gridHeight,
      influenceMap: matte,
      intensity: intensity,
      parameters: parameters,
      fse: _faceShortEdgePx(face, imageSize),
      directMesh: directMesh,
      // face_slim: malha backward (V3_MESH) — sem vacancy na grade.
      applyVacancyFill: !mvpMeshPath &&
          (!interactivePreview || exporting) &&
          FaceWarpVacancyFill.hasActiveLateralTool(parameters),
    );

    if (FaceWarpV3Config.useGpuPiecewiseAffine) {
      return field.copyWith(passId: 'face_mesh_v3_gpu');
    }
    return field;
  }

  /// Payload GPU piecewise-affine (Sprint 37).
  FaceMeshGpuPayload? composeGpuPayload({
    required FaceMeshResult face,
    required TriMesh mesh,
    required Size imageSize,
    required Map<String, double> parameters,
    PersonMask? personMask,
  }) {
    if (!FaceWarpV3Config.useGpuPiecewiseAffine) {
      return null;
    }
    if (!const FaceFilterPipeline().hasActiveWarp(parameters)) {
      return null;
    }

    final context = FaceAnatomyContext(
      face: face,
      imageSize: imageSize,
      mesh: mesh,
    );

    final vertexField = composeVertexField(
      parameters: parameters,
      context: context,
      mesh: mesh,
    );

    if (vertexField.maxDisplacementMagnitude() <= _minVertexDisplacementPx) {
      return null;
    }

    final mvpMeshPath = FaceWarpVacancyFill.usesMvpMeshPath(parameters);
    final matte = FaceMatteRoi.buildInfluenceMap(
      face: face,
      imageSize: imageSize,
      personMask: personMask,
      lateralRadiusExpand: mvpMeshPath ? 0.07 : 0.0,
    );

    return FaceMeshGpuPayload.build(
      mesh: mesh,
      vertexField: vertexField,
      imageSize: imageSize,
      influenceMap: matte,
      intensity: _peakIntensity(parameters),
    );
  }

  static double _faceShortEdgePx(FaceMeshResult face, Size imageSize) {
    final oval = MeshTopology.faceRegionLandmarks[MeshRegion.faceOval];
    if (oval == null) {
      return math.min(imageSize.width, imageSize.height);
    }
    final bounds = FaceWarpUtils.landmarkBounds(face, imageSize, oval);
    if (bounds == null || bounds.isEmpty) {
      return math.min(imageSize.width, imageSize.height);
    }
    return math.min(bounds.width, bounds.height);
  }

  static double _peakIntensity(Map<String, double> parameters) {
    var peak = 0.0;
    for (final key in FaceFilterPipeline.faceWarpParameterKeys) {
      final v = parameters[key] ?? 0;
      if (v > peak) {
        peak = v;
      }
    }
    return peak;
  }

  /// Estatísticas de debug a partir do campo de vértices.
  static FaceWarpDebugStats debugStatsFor(ConstrainedVertexField field) {
    var moved = 0;
    const threshold = 0.05;
    for (var i = 0; i < field.landmarkCount; i++) {
      if (field.displacementAt(i).distance > threshold) {
        moved++;
      }
    }
    return FaceWarpDebugStats(
      movedVertices: moved,
      vertexMaxPx: field.maxDisplacementMagnitude(),
      rigidPinnedVertices: field.rigidPinnedVertices,
    );
  }
}
