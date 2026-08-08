import 'texture_handle.dart';

/// Alvo de render (textura de saida de um pass).
class RenderTarget {
  final TextureHandle texture;
  final String passName;

  const RenderTarget({
    required this.texture,
    required this.passName,
  });
}

/// Estagio de pipeline multi-pass.
class RenderPipelineStage {
  final String shaderName;
  final Map<String, Object> uniforms;

  const RenderPipelineStage({
    required this.shaderName,
    this.uniforms = const {},
  });
}

/// Nomes de shaders/passes registrados.
abstract class RenderShaders {
  static const warpRemap = 'warp_remap';
  static const colorAdjust = 'color_adjust';
  static const colorGrade = 'color_grade';
  static const lutApply = 'lut_apply';
  static const composite = 'composite';
  static const eyeOverlay = 'eye_overlay';
  static const cheekboneContour = 'cheekbone_contour';
  static const skinEngine = 'skin_engine';
  static const makeupBlend = 'makeup_blend';
}
