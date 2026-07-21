import 'render_pass.dart';
import 'pass_cheekbone_contour.dart';
import 'pass_color.dart';
import 'pass_composite.dart';
import 'pass_eye_overlay.dart';
import 'pass_lut.dart';
import 'pass_skin_engine.dart';
import 'pass_warp.dart';
import 'render_target.dart';

/// Cache de passes/shaders registrados.
class ShaderProgramCache {
  ShaderProgramCache({Map<String, RenderPass>? passes})
      : _passes = passes ?? _defaultPasses();

  final Map<String, RenderPass> _passes;

  static Map<String, RenderPass> _defaultPasses() {
    const warp = PassWarp();
    const color = PassColor();
    final lut = PassLut();
    const composite = PassComposite();
    const eyeOverlay = PassEyeOverlay();
    const cheekboneContour = PassCheekboneContour();
    const skinEngine = PassSkinEngine();
    return {
      RenderShaders.warpRemap: warp,
      RenderShaders.colorAdjust: color,
      RenderShaders.lutApply: lut,
      RenderShaders.composite: composite,
      RenderShaders.eyeOverlay: eyeOverlay,
      RenderShaders.cheekboneContour: cheekboneContour,
      RenderShaders.skinEngine: skinEngine,
    };
  }

  RenderPass getPass(String shaderName) {
    final pass = _passes[shaderName];
    if (pass == null) {
      throw ArgumentError('Unknown shader/pass: $shaderName');
    }
    return pass;
  }

  bool contains(String shaderName) => _passes.containsKey(shaderName);

  Iterable<String> get registeredShaders => _passes.keys;
}
