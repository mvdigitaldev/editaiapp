import 'dart:math' as math;
import 'dart:ui';

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
  const BodyFilterPipeline();

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

  static const bodyWarpParameterKeys = [
    'waist_slim',
    'hip',
    'body_slim',
    'leg_length',
    'leg_slim',
    'arm_slim',
    'neck_slim',
    'shoulder_width',
  ];

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

  /// Retorna false se pose parcial/confiança baixa para os filtros pedidos.
  bool canApply(PoseResult pose, Map<String, double> parameters) {
    if (!hasActiveBodyWarp(parameters)) {
      return false;
    }

    final activeFilters = allFilters.where(
      (filter) => _readParameter(parameters, filter.parameterKey) > 0,
    );

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
    if (passes <= 1) {
      return builder.build(
        controlPoints: controlPoints,
        imageSize: imageSize,
        region: MeshRegion.torso,
        intensity: maxIntensity,
        personMask: personMask,
      );
    }

    final scaled = BodyWarpUtils.scaleControlPointDeltas(
      controlPoints,
      1.0 / passes,
    );
    var field = builder.build(
      controlPoints: scaled,
      imageSize: imageSize,
      region: MeshRegion.torso,
      intensity: maxIntensity,
      personMask: personMask,
    );
    for (var i = 1; i < passes; i++) {
      final next = builder.build(
        controlPoints: scaled,
        imageSize: imageSize,
        region: MeshRegion.torso,
        intensity: maxIntensity,
        personMask: personMask,
      );
      field = WarpField.composeSequential(field, next);
    }
    return field;
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
    if (parameters.containsKey(snakeKey)) {
      return parameters[snakeKey]!.clamp(0.0, 1.0);
    }
    final camel = _toCamelCase(snakeKey);
    if (parameters.containsKey(camel)) {
      return parameters[camel]!.clamp(0.0, 1.0);
    }
    return 0;
  }

  String _toCamelCase(String snake) {
    final parts = snake.split('_');
    if (parts.isEmpty) {
      return snake;
    }
    final buffer = StringBuffer(parts.first);
    for (var i = 1; i < parts.length; i++) {
      final part = parts[i];
      if (part.isEmpty) {
        continue;
      }
      buffer.write(part[0].toUpperCase());
      if (part.length > 1) {
        buffer.write(part.substring(1));
      }
    }
    return buffer.toString();
  }
}
