import 'dart:ui';

import '../../models/mesh_region.dart';
import '../../models/pose_result.dart';
import '../../models/tri_mesh.dart';
import '../../models/warp_field.dart';
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
  }) {
    if (!canApply(pose, parameters)) {
      return WarpField.identity(imageSize: imageSize, region: MeshRegion.torso);
    }

    final controlPoints = <ControlPoint>[];
    var maxIntensity = 0.0;

    for (final filter in allFilters) {
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

    return builder.build(
      controlPoints: controlPoints,
      imageSize: imageSize,
      region: MeshRegion.torso,
      intensity: maxIntensity,
    );
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
