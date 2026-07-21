import '../models/warp_algorithm.dart';
import '../models/warp_field.dart';
import '../rendering/gpu_renderer.dart';
import '../rendering/texture_handle.dart';

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
}