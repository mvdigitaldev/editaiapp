import '../body_reshape/passes/body_multi_pass_pipeline.dart';
import '../models/warp_algorithm.dart';
import '../models/warp_field.dart';
import '../rendering/gpu_renderer.dart';

export '../body_reshape/passes/body_multi_pass_pipeline.dart'
    show BodyMultiPassInput, BodyMultiPassResult, BodyMultiPassPipeline;
export '../body_reshape/passes/pass_profiler.dart'
    show BodyMultiPassConfig, PassProfiler, PassProfileEntry;
export '../models/warp_field.dart' show WarpField, WarpRequest;

/// Motor de deformacao geometrica (MLS default).
abstract class WarpEngine {
  static const warpRemapShader = 'warp_remap';

  WarpAlgorithm get algorithm;

  WarpField compute(WarpRequest request);

  Future<TextureHandle> applyGPU({
    required TextureHandle input,
    required WarpField field,
    required GPURenderer renderer,
  });

  /// Pipeline multi-passe Body Reshape V2 (Sprint 10).
  ///
  /// Implementações que não suportam devem retornar null.
  BodyMultiPassResult? composeBodyMultiPass(BodyMultiPassInput input);
}
