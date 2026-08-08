import 'dart:typed_data';
import 'dart:ui';

import '../../models/face_mesh_result.dart';
import '../../models/tune_params.dart';
import '../../rendering/render_target.dart';
import '../../segment/face_parts_segmentation.dart';

/// Orquestra o pass de cor global (Grupo D — Sprint 2).
class ColorFilterPipeline {
  const ColorFilterPipeline();

  static const colorParameterKeys = [
    'brightness',
    'contrast',
    'saturation',
    'exposure',
    'temperature',
    'tint',
    'vibrance',
    'hue',
    'highlights',
    'shadows',
    'whites',
    'blacks',
    'fade',
    'sharpness',
    'luminance',
    'vignette',
    'gamma',
  ];

  static bool isColorKey(String key) => colorParameterKeys.contains(key);

  bool hasActiveColor(Map<String, double> parameters) {
    for (final key in colorParameterKeys) {
      if (_read(parameters, key).abs() > 1e-6) {
        return true;
      }
    }
    return false;
  }

  TuneParams extractTuneParams(Map<String, double> parameters) {
    return TuneParams(
      brightness: _read(parameters, 'brightness'),
      contrast: _read(parameters, 'contrast'),
      saturation: _read(parameters, 'saturation'),
      exposure: _read(parameters, 'exposure'),
      temperature: _read(parameters, 'temperature'),
      tint: _read(parameters, 'tint'),
      vibrance: _read(parameters, 'vibrance'),
      hue: _read(parameters, 'hue'),
      highlights: _read(parameters, 'highlights'),
      shadows: _read(parameters, 'shadows'),
      whites: _read(parameters, 'whites'),
      blacks: _read(parameters, 'blacks'),
      fade: _read(parameters, 'fade'),
      sharpness: _read(parameters, 'sharpness'),
      luminance: _read(parameters, 'luminance'),
      vignette: _read(parameters, 'vignette'),
      gamma: _read(parameters, 'gamma'),
    );
  }

  List<RenderPipelineStage> buildColorStages({
    required Map<String, double> parameters,
    FaceMeshResult? face,
    Size? imageSize,
    FacePartsSegmentation? faceParts,
    Float32List? skinProtectionWeights,
  }) {
    if (!hasActiveColor(parameters)) {
      return const [];
    }

    final uniforms = <String, Object>{
      'tune': extractTuneParams(parameters),
    };
    if (skinProtectionWeights != null && skinProtectionWeights.isNotEmpty) {
      uniforms['skinProtection'] = skinProtectionWeights;
    } else if (face != null && imageSize != null) {
      uniforms['face'] = face;
      uniforms['imageSize'] = imageSize;
      if (faceParts != null && !faceParts.isEmpty) {
        uniforms['faceParts'] = faceParts;
      }
    }

    return [
      RenderPipelineStage(
        shaderName: RenderShaders.colorGrade,
        uniforms: uniforms,
      ),
    ];
  }

  double _read(Map<String, double> parameters, String key) {
    return parameters[key] ?? 0;
  }
}
