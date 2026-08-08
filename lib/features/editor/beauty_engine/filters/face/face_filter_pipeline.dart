import 'dart:ui';

import '../../models/face_mesh_result.dart';
import '../../models/mesh_region.dart';
import '../../models/tri_mesh.dart';
import '../../models/warp_field.dart';
import '../../warp/models/control_point.dart';
import '../../warp/warp_field_builder.dart';
import 'cheekbone.dart';
import 'chin.dart';
import 'double_eyelid.dart';
import 'eye_distance.dart';
import 'eye_height.dart';
import 'eye_rotation.dart';
import 'eye_scale.dart';
import 'face_slim.dart';
import 'face_influence_map_builder.dart';
import 'face_warp_context.dart';
import 'face_warp_filter.dart';
import 'face_warp_region.dart';
import 'face_warp_utils.dart';
import 'forehead.dart';
import 'head_size.dart';
import 'jaw.dart';
import 'lip_thickness.dart';
import 'mouth_width.dart';
import 'narrow_face.dart';
import 'nose_bridge.dart';
import 'nose_height.dart';
import 'nose_length.dart';
import 'nose_slim.dart';
import 'nose_tip.dart';
import 'smile.dart';
import 'temple.dart';
import 'v_face.dart';

/// Pipeline composável de filtros faciais warp (Sprint 10–16).
class FaceFilterPipeline {
  const FaceFilterPipeline({
    WarpFieldBuilder? fieldBuilder,
  }) : _fieldBuilder = fieldBuilder;

  /// Um builder injetado preserva as grades determinísticas dos testes.
  /// Sem injeção, a grade acompanha a resolução para não ampliar degraus em
  /// preview/export de alta resolução.
  final WarpFieldBuilder? _fieldBuilder;

  static final allFilters = <FaceWarpFilter>[
    FaceSlimFilter(),
    NarrowFaceFilter(),
    VFaceFilter(),
    NoseSlimFilter(),
    NoseLengthFilter(),
    NoseHeightFilter(),
    NoseTipFilter(),
    NoseBridgeFilter(),
    EyeScaleFilter(),
    EyeDistanceFilter(),
    EyeHeightFilter(),
    EyeRotationFilter(),
    DoubleEyelidFilter(),
    JawFilter(),
    ChinFilter(),
    HeadSizeFilter(),
    CheekboneFilter(),
    ForeheadFilter(),
    TempleFilter(),
    MouthWidthFilter(),
    LipThicknessFilter(),
    SmileFilter(),
  ];

  static const faceWarpParameterKeys = [
    'face_slim',
    'narrow_face',
    'v_face',
    'nose_slim',
    'nose_length',
    'nose_height',
    'nose_tip',
    'nose_bridge',
    'eye_scale',
    'eye_distance',
    'eye_height',
    'eye_rotation',
    'double_eyelid',
    'jaw',
    'chin',
    'head_size',
    'cheekbone',
    'forehead',
    'temple',
    'mouth_width',
    'lip_thickness',
    'smile',
  ];

  WarpField compose({
    required TriMesh mesh,
    required FaceMeshResult face,
    required Size imageSize,
    required Map<String, double> parameters,
    bool unified = false,
  }) {
    if (unified) {
      return _composeUnified(
        mesh: mesh,
        face: face,
        imageSize: imageSize,
        parameters: parameters,
      );
    }
    return _composeRegional(
      mesh: mesh,
      face: face,
      imageSize: imageSize,
      parameters: parameters,
    );
  }

  WarpField _composeUnified({
    required TriMesh mesh,
    required FaceMeshResult face,
    required Size imageSize,
    required Map<String, double> parameters,
  }) {
    final yawFactor = FaceWarpUtils.yawClampFactor(face);
    final linkEyes = _readLinkEyes(parameters);
    final builder = _fieldBuilder ?? WarpFieldBuilder.forImageSize(imageSize);
    final controlPoints = <ControlPoint>[];
    var maxIntensity = 0.0;

    for (final filter in allFilters) {
      final raw = _readParameter(parameters, filter.parameterKey);
      if (raw <= 0) {
        continue;
      }
      final warpContext = FaceWarpContext(
        mesh: mesh,
        face: face,
        imageSize: imageSize,
        intensity: raw,
        yawFactor: yawFactor,
        linkEyes: linkEyes,
      );
      controlPoints.addAll(filter.buildControlPoints(warpContext));
      if (warpContext.effectiveIntensity > maxIntensity) {
        maxIntensity = warpContext.effectiveIntensity;
      }
    }

    if (controlPoints.isEmpty || maxIntensity <= 0) {
      return WarpField.identity(
        imageSize: imageSize,
        region: MeshRegion.faceOval,
      );
    }

    // Preview: um único MLS com cápsula — contínuo, sem artefato de camadas.
    return builder.build(
      controlPoints: controlPoints,
      imageSize: imageSize,
      region: MeshRegion.faceOval,
      intensity: maxIntensity,
    );
  }

  WarpField _composeRegional({
    required TriMesh mesh,
    required FaceMeshResult face,
    required Size imageSize,
    required Map<String, double> parameters,
  }) {
    final yawFactor = FaceWarpUtils.yawClampFactor(face);
    final linkEyes = _readLinkEyes(parameters);
    final builder = _fieldBuilder ?? WarpFieldBuilder.forImageSize(imageSize);

    final filtersByRegion = <FaceWarpRegion, List<FaceWarpFilter>>{};
    for (final filter in allFilters) {
      if (_readParameter(parameters, filter.parameterKey) <= 0) {
        continue;
      }
      final region = FaceWarpRegionMap.regionForKey(filter.parameterKey);
      if (region == null) {
        continue;
      }
      filtersByRegion.putIfAbsent(region, () => []).add(filter);
    }

    if (filtersByRegion.isEmpty) {
      return WarpField.identity(
        imageSize: imageSize,
        region: MeshRegion.faceOval,
      );
    }

    WarpField? composed;
    for (final region in FaceWarpRegionMap.regionOrder) {
      final filters = filtersByRegion[region];
      if (filters == null || filters.isEmpty) {
        continue;
      }

      final controlPoints = <ControlPoint>[];
      var maxIntensity = 0.0;
      for (final filter in filters) {
        final raw = _readParameter(parameters, filter.parameterKey);
        final warpContext = FaceWarpContext(
          mesh: mesh,
          face: face,
          imageSize: imageSize,
          intensity: raw,
          yawFactor: yawFactor,
          linkEyes: linkEyes,
        );
        controlPoints.addAll(filter.buildControlPoints(warpContext));
        if (warpContext.effectiveIntensity > maxIntensity) {
          maxIntensity = warpContext.effectiveIntensity;
        }
      }

      if (controlPoints.isEmpty || maxIntensity <= 0) {
        continue;
      }

      final influenceMap = FaceInfluenceMapBuilder.build(
        region: region,
        face: face,
        imageSize: imageSize,
      );

      final field = builder.build(
        controlPoints: controlPoints,
        imageSize: imageSize,
        region: MeshRegion.faceOval,
        intensity: maxIntensity,
        influenceMap: influenceMap,
      );

      if (field.isIdentity) {
        continue;
      }

      composed = composed == null
          ? field
          : WarpField.composeSequential(field, composed);
    }

    return composed ??
        WarpField.identity(imageSize: imageSize, region: MeshRegion.faceOval);
  }

  bool hasActiveWarp(Map<String, double> parameters) {
    for (final key in faceWarpParameterKeys) {
      if (_readParameter(parameters, key) > 0) {
        return true;
      }
    }
    return false;
  }

  bool _readLinkEyes(Map<String, double> parameters) {
    if (parameters.containsKey('link_eyes')) {
      return parameters['link_eyes']! >= 0.5;
    }
    if (parameters.containsKey('linkEyes')) {
      return parameters['linkEyes']! >= 0.5;
    }
    return true;
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
