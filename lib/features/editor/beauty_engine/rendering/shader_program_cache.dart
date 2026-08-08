import '../body_reshape/rendering/fragment_program_warp_backend.dart';
import '../filters/face/skin/native_skin_backend.dart';
import 'render_pass.dart';
import 'pass_cheekbone_contour.dart';
import 'pass_color.dart';
import 'pass_color_grade.dart';
import 'pass_composite.dart';
import 'pass_eye_overlay.dart';
import 'pass_lut.dart';
import 'pass_makeup_blend.dart';
import 'pass_skin_engine.dart';
import 'pass_warp.dart';
import 'render_target.dart';

/// Cache de passes/shaders registrados.
class ShaderProgramCache {
  ShaderProgramCache({
    Map<String, RenderPass>? passes,
    FragmentProgramWarpBackend? warpBackend,
    NativeSkinBackend? nativeSkinBackend,
    bool preferGpuWarp = true,
  }) : _passes = passes ??
            _defaultPasses(
              warpBackend: warpBackend,
              nativeSkinBackend: nativeSkinBackend,
              preferGpuWarp: preferGpuWarp,
            );

  final Map<String, RenderPass> _passes;

  static Map<String, RenderPass> _defaultPasses({
    FragmentProgramWarpBackend? warpBackend,
    NativeSkinBackend? nativeSkinBackend,
    bool preferGpuWarp = true,
  }) {
    final warp = PassWarp(
      warpBackend: warpBackend,
      preferGpu: preferGpuWarp,
    );
    const color = PassColor();
    const colorGrade = PassColorGrade();
    final lut = PassLut();
    const composite = PassComposite();
    const eyeOverlay = PassEyeOverlay();
    const cheekboneContour = PassCheekboneContour();
    const makeupBlend = PassMakeupBlend();
    final skinEngine = PassSkinEngine(nativeSkinBackend: nativeSkinBackend);
    return {
      RenderShaders.warpRemap: warp,
      RenderShaders.colorAdjust: color,
      RenderShaders.colorGrade: colorGrade,
      RenderShaders.lutApply: lut,
      RenderShaders.composite: composite,
      RenderShaders.eyeOverlay: eyeOverlay,
      RenderShaders.cheekboneContour: cheekboneContour,
      RenderShaders.makeupBlend: makeupBlend,
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
