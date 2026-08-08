import 'dart:ui';

import '../../models/face_mesh_result.dart';
import '../../models/warp_field.dart';
import '../../rendering/render_target.dart';
import '../../segment/face_parts_segmentation.dart';
import '../../segment/face_parsing_result.dart';
import 'skin/skin_weight_map.dart';
import 'skin_mask_utils.dart';

/// Orquestra passes de pele/makeup (Sprint 17).
class SkinFilterPipeline {
  const SkinFilterPipeline();

  static const skinParameterKeys = [
    'skin_smooth',
    'skin_whitening',
    'remove_acne',
    'remove_wrinkles',
    'remove_dark_circles',
    'skin_shine',
    'teeth_whitening',
    'blush',
    'contour',
    'eyebrows',
    'eyelashes',
    'iris_enhance',
  ];

  /// Makeup overlays (CPU darken) — ocultos no lab nativo até Sprint 42+.
  static const makeupParameterKeys = {
    'blush',
    'contour',
    'eyebrows',
    'eyelashes',
  };

  /// Keys visíveis no painel de ajustes.
  static List<String> uiParameterKeys({required bool labMode}) {
    if (!labMode) {
      return skinParameterKeys;
    }
    return skinParameterKeys
        .where((key) => !makeupParameterKeys.contains(key))
        .toList(growable: false);
  }

  bool hasActiveSkin(Map<String, double> parameters) {
    for (final key in skinParameterKeys) {
      if (_read(parameters, key) > 0) {
        return true;
      }
    }
    return false;
  }

  /// Parsing semântico (BiSeNet/mapper) só é necessário para retouch e
  /// makeup que dependem de máscaras derivadas — não para clarear pele/blush.
  bool needsSemanticParsing(Map<String, double> parameters) {
    const parsingKeys = {
      'skin_smooth',
      'remove_acne',
      'remove_wrinkles',
      'remove_dark_circles',
      'skin_shine',
      'teeth_whitening',
      'contour',
      'eyebrows',
      'eyelashes',
      'iris_enhance',
    };
    for (final key in parsingKeys) {
      if (_read(parameters, key) > 0) {
        return true;
      }
    }
    return false;
  }

  List<RenderPipelineStage> buildPostStages({
    required Map<String, double> parameters,
    required FaceMeshResult face,
    required Size imageSize,
    FacePartsSegmentation? faceParts,
    FaceParsingResult? faceParsing,
    WarpField? faceWarp,
    Offset tileOrigin = Offset.zero,
  }) {
    if (!hasActiveSkin(parameters)) {
      return const [];
    }

    final mask = SkinMaskUtils.build(face, imageSize);
    if (mask.isEmpty) {
      return const [];
    }

    final uniforms = <String, Object>{
      'mask': mask,
      'tileMapping': SkinTileMapping(
        originX: tileOrigin.dx.round(),
        originY: tileOrigin.dy.round(),
        fullWidth: imageSize.width.round(),
        fullHeight: imageSize.height.round(),
      ),
    };
    if (faceParts != null && !faceParts.isEmpty) {
      uniforms['faceParts'] = faceParts;
    }
    if (faceParsing != null && !faceParsing.isEmpty) {
      uniforms['faceParsing'] = faceParsing;
    }
    if (faceWarp != null && !faceWarp.isIdentity) {
      uniforms['faceWarp'] = faceWarp;
    }
    for (final key in skinParameterKeys) {
      uniforms[key] = _read(parameters, key);
    }

    return [
      RenderPipelineStage(
        shaderName: RenderShaders.skinEngine,
        uniforms: uniforms,
      ),
    ];
  }

  double _read(Map<String, double> parameters, String snakeKey) {
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
