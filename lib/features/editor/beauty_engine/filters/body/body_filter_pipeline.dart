import 'dart:math' as math;
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
import '../../warp/models/control_point.dart';
import '../../warp/warp_field_builder.dart';
import 'arm_slim.dart';
import 'body_slim.dart';
import 'body_warp_context.dart';
import 'body_warp_filter.dart';
import 'body_warp_utils.dart';
import 'hip.dart';
import 'leg_length.dart';
import 'leg_slim.dart';
import 'neck_slim.dart';
import 'shoulder_width.dart';
import 'waist_slim.dart';

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

  static final allFilters = <BodyWarpFilter>[
    WaistSlimFilter(),
    HipFilter(),
    BodySlimFilter(),
    LegLengthFilter(),
    LegSlimFilter(),
    ArmSlimFilter(),
    NeckSlimFilter(),
    ShoulderWidthFilter(),
  ];

  static const bodyWarpParameterKeys =
      LegacyBodyParameterAdapter.supportedParameterKeys;

  static const _legKeys = {'leg_length', 'leg_slim'};
  static const _unifiedTorsoKeys = {'waist_slim', 'body_slim'};

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

  /// Retorna false se pose parcial/confiança baixa para os filtros pedidos.
  bool canApply(PoseResult pose, Map<String, double> parameters) {
    if (!hasActiveBodyWarp(parameters)) {
      return false;
    }

    final activeFilters = allFilters.where(
      (filter) => _readParameter(parameters, filter.parameterKey) > 0,
    );

    // Controles só V2: exige pose mínima (ombros/quadril) via confidence torso.
    if (activeFilters.isEmpty &&
        LegacyBodyParameterAdapter.requiresV2Mesh(parameters)) {
      final confidence = BodyWarpUtils.poseConfidence(
        pose,
        const {11, 12, 23, 24},
      );
      return confidence >= BodyWarpUtils.visibilityThreshold;
    }

    for (final filter in activeFilters) {
      if (_legKeys.contains(filter.parameterKey) && pose.isPartial) {
        return false;
      }
      final confidence = BodyWarpUtils.poseConfidence(
        pose,
        filter.requiredPoseIndices,
      );
      if (confidence < BodyWarpUtils.visibilityThreshold) {
        return false;
      }
    }

    return true;
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
    if (!canApply(pose, parameters)) {
      return WarpField.identity(imageSize: imageSize, region: MeshRegion.torso);
    }

    final controlPoints = <ControlPoint>[];
    var maxIntensity = 0.0;

    // Waist + body num único solve (evita CPs duplicados / folding).
    final torsoPoints = _buildUnifiedTorsoSlim(
      mesh: mesh,
      pose: pose,
      imageSize: imageSize,
      parameters: parameters,
      personMask: personMask,
    );
    if (torsoPoints != null) {
      controlPoints.addAll(torsoPoints.points);
      maxIntensity = maxIntensity > torsoPoints.intensity
          ? maxIntensity
          : torsoPoints.intensity;
    }

    for (final filter in allFilters) {
      if (_unifiedTorsoKeys.contains(filter.parameterKey)) {
        continue;
      }

      final raw = _readParameter(parameters, filter.parameterKey);
      if (raw <= 0) {
        continue;
      }

      final confidence = BodyWarpUtils.poseConfidence(
        pose,
        filter.requiredPoseIndices,
      );
      final warpContext = BodyWarpContext(
        mesh: mesh,
        pose: pose,
        imageSize: imageSize,
        intensity: raw,
        confidenceFactor: confidence,
        personMask: personMask,
        protectionMaps: protectionMaps,
        influenceMap: influenceMap,
        frameAssets: frameAssets,
      );

      controlPoints.addAll(filter.buildControlPoints(warpContext));
      maxIntensity = maxIntensity > warpContext.effectiveIntensity
          ? maxIntensity
          : warpContext.effectiveIntensity;
    }

    if (controlPoints.isEmpty || maxIntensity <= 0) {
      return WarpField.identity(imageSize: imageSize, region: MeshRegion.torso);
    }

    final quality = interactive
        ? WarpFieldQuality.interactive
        : (imageSize.width * imageSize.height >= 700000
            ? WarpFieldQuality.export
            : WarpFieldQuality.preview);
    final builder = WarpFieldBuilder.forImageSize(
      imageSize,
      quality: quality,
    );

    final passes = _passCount(maxIntensity, interactive: interactive);
    late WarpField field;
    if (passes <= 1) {
      field = builder.build(
        controlPoints: controlPoints,
        imageSize: imageSize,
        region: MeshRegion.torso,
        intensity: maxIntensity,
        personMask: personMask,
        protectionMaps: protectionMaps,
        influenceMap: influenceMap,
      );
    } else {
      final scaled = BodyWarpUtils.scaleControlPointDeltas(
        controlPoints,
        1.0 / passes,
      );
      field = builder.build(
        controlPoints: scaled,
        imageSize: imageSize,
        region: MeshRegion.torso,
        intensity: maxIntensity,
        personMask: personMask,
        protectionMaps: protectionMaps,
        influenceMap: influenceMap,
      );
      for (var i = 1; i < passes; i++) {
        final next = builder.build(
          controlPoints: scaled,
          imageSize: imageSize,
          region: MeshRegion.torso,
          intensity: maxIntensity,
          personMask: personMask,
          protectionMaps: protectionMaps,
          influenceMap: influenceMap,
        );
        field = WarpField.composeSequential(field, next);
      }
    }

    return applyBackgroundProtection(
      field: field,
      rigidityMap: rigidityMap,
      backgroundProtection: backgroundProtection,
    );
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

  ({List<ControlPoint> points, double intensity})? _buildUnifiedTorsoSlim({
    required TriMesh mesh,
    required PoseResult pose,
    required Size imageSize,
    required Map<String, double> parameters,
    PersonMask? personMask,
  }) {
    final waistRaw = _readParameter(parameters, 'waist_slim');
    final bodyRaw = _readParameter(parameters, 'body_slim');
    if (waistRaw <= 0 && bodyRaw <= 0) {
      return null;
    }

    final confidence = BodyWarpUtils.poseConfidence(pose, {11, 12, 23, 24});
    if (confidence < BodyWarpUtils.visibilityThreshold) {
      return null;
    }

    final waist = (waistRaw * confidence).clamp(0.0, 1.0);
    final body = (bodyRaw * confidence).clamp(0.0, 1.0);
    final waistT = waist * waist * (3 - 2 * waist);
    final bodyT = body * body * (3 - 2 * body);

    final leftTop = BodyWarpUtils.vertexAt(mesh, 11);
    final rightTop = BodyWarpUtils.vertexAt(mesh, 12);
    final leftBottom = BodyWarpUtils.vertexAt(mesh, 23);
    final rightBottom = BodyWarpUtils.vertexAt(mesh, 24);
    if (leftTop == null ||
        rightTop == null ||
        leftBottom == null ||
        rightBottom == null) {
      return null;
    }

    // Shift unificado: body cobre base; waist reforça o miolo (sem somar 100%).
    final baseShift = imageSize.width * (0.045 * bodyT + 0.055 * waistT);
    // Perfil: body mais plano; waist pico no meio.
    final profileFloor = 0.40 + 0.25 * bodyT;
    final profilePeak = (0.70 + 0.30 * bodyT + 0.35 * waistT).clamp(0.0, 1.15);

    final movable = BodyWarpUtils.slimTorsoSides(
      leftTop: leftTop,
      rightTop: rightTop,
      leftBottom: leftBottom,
      rightBottom: rightBottom,
      imageSize: imageSize,
      shiftPx: baseShift,
      samples: waistT > 0.3 ? 8 : 6,
      personMask: personMask,
      profileFloor: profileFloor,
      profilePeak: profilePeak,
    );

    if (movable.isEmpty) {
      return null;
    }

    final points = <ControlPoint>[
      ...BodyWarpUtils.anchorPoints(
        mesh,
        excludeIndices: {11, 12, 23, 24},
      ),
      ...movable,
      ...BodyWarpUtils.backgroundFreezeRing(
        movable: movable,
        imageSize: imageSize,
        ringScale: 1.72,
      ),
    ];

    return (
      points: points,
      intensity: math.max(waist, body),
    );
  }

  int _passCount(double intensity, {required bool interactive}) {
    if (interactive) {
      return intensity >= 0.85 ? 2 : 1;
    }
    if (intensity >= 0.8) return 4;
    if (intensity >= 0.55) return 3;
    return 1;
  }

  double _readParameter(Map<String, double> parameters, String snakeKey) {
    return LegacyBodyParameterAdapter.readParameter(parameters, snakeKey);
  }
}
