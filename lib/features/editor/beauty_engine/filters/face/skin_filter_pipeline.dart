import 'dart:math' as math;
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
    final dark = darkCircleSides(parameters);
    return dark.left > 0 || dark.right > 0;
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
    final dark = darkCircleSides(parameters);
    return dark.left > 0 || dark.right > 0;
  }

  /// Intensidade de olheiras. Um slider só, os dois olhos.
  ///
  /// O slider de Olhos (`eye_puffy`) e o de Pele (`remove_dark_circles`)
  /// alimentam o mesmo clareamento. O maior dos dois vale. Chaves
  /// `eye_puffy_left` / `eye_puffy_right` antigas não escolhem um olho:
  /// entram no mesmo máximo.
  ({double left, double right}) darkCircleSides(
    Map<String, double> parameters,
  ) {
    final skin = _read(parameters, 'remove_dark_circles');
    final general = _read(parameters, 'eye_puffy');
    final legacyLeft = (parameters['eye_puffy_left'] ?? 0).clamp(0.0, 1.0);
    final legacyRight = (parameters['eye_puffy_right'] ?? 0).clamp(0.0, 1.0);
    final intensity = math.max(
      skin,
      math.max(general, math.max(legacyLeft, legacyRight)),
    );
    return (left: intensity, right: intensity);
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
    final dark = darkCircleSides(parameters);
    uniforms['remove_dark_circles'] = math.max(dark.left, dark.right);
    uniforms['eye_dark_left'] = dark.left;
    uniforms['eye_dark_right'] = dark.right;

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
