import '../models/warp_algorithm.dart';
import '../rendering/gpu_renderer.dart';
import '../rendering/texture_handle.dart';
import 'warp_engine.dart';

/// Stub MLS — delega identidade (usar [MlsWarpEngine] em producao).
class WarpEngineStub implements WarpEngine {
  const WarpEngineStub();

  @override
  WarpAlgorithm get algorithm => WarpAlgorithm.mls;

  @override
  WarpField compute(WarpRequest request) {
    return WarpField.identity(
      imageSize: request.imageSize,
      region: request.region,
    );
  }

  @override
  Future<TextureHandle> applyGPU({
    required TextureHandle input,
    required WarpField field,
    required GPURenderer renderer,
  }) async {
    return input;
  }
}
