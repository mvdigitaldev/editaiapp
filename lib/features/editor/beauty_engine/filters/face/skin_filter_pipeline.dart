import 'dart:ui';

import '../../models/face_mesh_result.dart';
import '../../rendering/render_target.dart';
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
    'teeth_whitening',
    'blush',
    'contour',
    'eyebrows',
    'eyelashes',
  ];

  bool hasActiveSkin(Map<String, double> parameters) {
    for (final key in skinParameterKeys) {
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
  }) {
    if (!hasActiveSkin(parameters)) {
      return const [];
    }

    final mask = SkinMaskUtils.build(face, imageSize);
    if (mask.isEmpty) {
      return const [];
    }

    final uniforms = <String, Object>{'mask': mask};
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
