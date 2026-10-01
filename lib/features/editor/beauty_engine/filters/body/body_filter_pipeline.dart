import 'dart:typed_data';
import 'dart:ui';

import '../../body_reshape/deformation/body_mesh_deformer.dart';
import '../../body_reshape/maps/influence_map.dart';
import '../../body_reshape/maps/influence_map_builder.dart';
import '../../body_reshape/maps/protection_maps.dart';
import '../../body_reshape/mesh/adaptive_body_mesh.dart';
import '../../body_reshape/mesh/mesh_optimizer.dart';
import '../../body_reshape/models/body_adjustment.dart';
import '../../body_reshape/models/body_frame_assets.dart';
import '../../body_reshape/models/body_region.dart';
import '../../body_reshape/models/body_reshape_request.dart';
import '../../body_reshape/models/legacy_body_parameter_adapter.dart';
import '../../body_reshape/models/warp_plan.dart';
import '../../body_reshape/protection/background_protector.dart';
import '../../body_reshape/protection/rigidity_map.dart';
import '../../body_reshape/providers/vision_capabilities.dart';
import '../../body_reshape/providers/vision_capability_gate.dart';
import '../../models/mesh_region.dart';
import '../../models/pose_result.dart';
import '../../models/tri_mesh.dart';
import '../../models/warp_field.dart';
import '../../segment/person_mask.dart';
import 'body_warp_filter.dart';

/// Pipeline composável de filtros corporais (Sprint 18–20).
class BodyFilterPipeline {
  const BodyFilterPipeline({
    VisionCapabilityGate capabilityGate = const VisionCapabilityGate(),
    BodyMeshDeformer meshDeformer = const BodyMeshDeformer(),
    BackgroundProtector backgroundProtector = const BackgroundProtector(),
  })  : _capabilityGate = capabilityGate,
        _meshDeformer = meshDeformer,
        _backgroundProtector = backgroundProtector;

  static const _parameterAdapter = LegacyBodyParameterAdapter();
  final VisionCapabilityGate _capabilityGate;
  final BodyMeshDeformer _meshDeformer;
  final BackgroundProtector _backgroundProtector;

  static final allFilters = <BodyWarpFilter>[];

  static const bodyWarpParameterKeys =
      LegacyBodyParameterAdapter.supportedParameterKeys;

  bool hasActiveBodyWarp(Map<String, double> parameters) {
    for (final key in bodyWarpParameterKeys) {
      if (_readParameter(parameters, key) > 0) {
        return true;
      }
    }
    return false;
  }

  /// Produz o plano semântico V2 sem alterar a execução do pipeline legado.
  ///
  /// Quando [capabilities] é informado, aplica [VisionCapabilityGate] para
  /// reduzir/recusar ajustes de risco sem fallback silencioso.
  WarpPlan createReshapePlan({
    required Size imageSize,
    required Map<String, double> parameters,
    bool interactive = false,
    VisionCapabilities? capabilities,
  }) {
    final profile = interactive
        ? WarpQualityProfile.interactive
        : (imageSize.width * imageSize.height >= 700000
            ? WarpQualityProfile.export
            : WarpQualityProfile.preview);
    final plan = _parameterAdapter.buildPlan(
      BodyReshapeRequest(
        imageSize: imageSize,
        parameters: parameters,
        qualityProfile: profile,
      ),
    );
    if (capabilities == null) {
      return plan;
    }
    return _capabilityGate.apply(plan: plan, capabilities: capabilities);
  }

  /// Deforma malha adaptativa V2 a partir de um [WarpPlan] (sem control points).
  ///
  /// O compose MLS legado permanece o caminho de produto até o backend GPU.
  OptimizedMeshResult deformAdaptiveMesh({
    required AdaptiveBodyMesh mesh,
    required BodyFrameAssets assets,
    required WarpPlan plan,
  }) {
    return _meshDeformer.deform(mesh: mesh, assets: assets, plan: plan);
  }

  /// Menu zerado: nenhum slider de corpo está activo.
  bool canApply(PoseResult _, Map<String, double> parameters) {
    return hasActiveBodyWarp(parameters);
  }

  WarpField compose({
    required TriMesh mesh,
    required PoseResult pose,
    required Size imageSize,
    required Map<String, double> parameters,
    bool interactive = false,
    PersonMask? personMask,
    InfluenceMap? influenceMap,
    BodyFrameAssets? frameAssets,
    ProtectionMaps? protectionMaps,
    RigidityMap? rigidityMap,
    BackgroundProtectionResult? backgroundProtection,
  }) {
    return WarpField.identity(imageSize: imageSize, region: MeshRegion.torso);
  }

  /// Aplica proteção estrutural de fundo a um campo já composto.
  WarpField applyBackgroundProtection({
    required WarpField field,
    RigidityMap? rigidityMap,
    BackgroundProtectionResult? backgroundProtection,
  }) {
    final protection = backgroundProtection;
    final rigidity = rigidityMap ?? protection?.rigidity;
    if (rigidity == null || rigidity.isEmpty) {
      return field;
    }
    return _backgroundProtector.applyToField(
      field: field,
      rigidity: rigidity,
      lines: protection?.lines,
    );
  }

  /// Analisa luminância/RGBA e produz edge/line/rigidity (Sprint 7).
  BackgroundProtectionResult analyzeBackground({
    required Size imageSize,
    ProtectionMaps? protection,
    Float32List? luminance,
    Uint8List? rgba,
    int? width,
    int? height,
    double confidence = 1,
    WarpQualityProfile qualityProfile = WarpQualityProfile.preview,
  }) {
    assert(
      (luminance != null && width != null && height != null) ||
          (rgba != null && width != null && height != null),
      'Informe luminance ou rgba com width/height',
    );
    if (rgba != null) {
      return _backgroundProtector.analyzeRgba(
        rgba: rgba,
        width: width!,
        height: height!,
        imageSize: imageSize,
        protection: protection,
        confidence: confidence,
        qualityProfile: qualityProfile,
      );
    }
    return _backgroundProtector.analyzeLuminance(
      luminance: luminance!,
      width: width!,
      height: height!,
      imageSize: imageSize,
      protection: protection,
      confidence: confidence,
      qualityProfile: qualityProfile,
    );
  }

  /// Influence Map V2 para um plano semântico (LOD pelo perfil de qualidade).
  InfluenceMap buildInfluenceMap({
    required WarpPlan plan,
    BodyFrameAssets? assets,
    ProtectionMaps? protection,
    AdaptiveBodyMesh? mesh,
    double confidence = 1,
  }) {
    final regions = <BodyRegion>{
      for (final adjustment in plan.adjustments)
        if (adjustment.isActive) ...adjustment.regions,
    };
    if (regions.isEmpty) {
      return InfluenceMap(
        values: Float32List(0),
        width: 0,
        height: 0,
        imageSize: plan.imageSize,
        regions: const {},
        confidence: confidence,
        maxValue: 0,
      );
    }

    // Usa o ajuste de maior intensidade como direção/limite dominante.
    BodyAdjustment? dominant;
    for (final adjustment in plan.adjustments) {
      if (!adjustment.isActive) continue;
      if (dominant == null ||
          adjustment.effectiveIntensity > dominant.effectiveIntensity) {
        dominant = adjustment;
      }
    }

    return const InfluenceMapBuilder().build(
      imageSize: plan.imageSize,
      regions: regions,
      assets: assets,
      mesh: mesh,
      protection: protection,
      adjustment: dominant,
      confidence: confidence,
      qualityProfile: plan.qualityProfile,
    );
  }

  double _readParameter(Map<String, double> parameters, String snakeKey) {
    return LegacyBodyParameterAdapter.readParameter(parameters, snakeKey);
  }
}
