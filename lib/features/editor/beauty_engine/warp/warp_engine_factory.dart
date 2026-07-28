import '../models/warp_algorithm.dart';
import '../rendering/gpu_renderer.dart';
import '../rendering/texture_handle.dart';
import 'mls_warp_engine.dart';
import 'warp_engine.dart';

/// Factory para engines de warp — TPS/ARAP retornam stub ate sprint futuro.
abstract class WarpEngineFactory {
  static WarpEngine create(WarpAlgorithm algorithm) {
    return switch (algorithm) {
      WarpAlgorithm.mls => MlsWarpEngine(),
      WarpAlgorithm.thinPlateSpline => const TpsWarpEngine(),
      WarpAlgorithm.arap => const ArapWarpEngine(),
      WarpAlgorithm.meshWarp => const MeshWarpEngine(),
    };
  }
}

/// Stub TPS — Sprint futuro.
class TpsWarpEngine implements WarpEngine {
  const TpsWarpEngine();

  @override
  WarpAlgorithm get algorithm => WarpAlgorithm.thinPlateSpline;

  @override
  WarpField compute(WarpRequest request) {
    throw UnimplementedError('TPS warp engine not yet implemented');
  }

  @override
  BodyMultiPassResult? composeBodyMultiPass(BodyMultiPassInput input) => null;

  @override
  Future<TextureHandle> applyGPU({
    required TextureHandle input,
    required WarpField field,
    required GPURenderer renderer,
  }) async {
    throw UnimplementedError('TPS warp engine not yet implemented');
  }
}

/// Stub ARAP — Sprint futuro.
class ArapWarpEngine implements WarpEngine {
  const ArapWarpEngine();

  @override
  WarpAlgorithm get algorithm => WarpAlgorithm.arap;

  @override
  WarpField compute(WarpRequest request) {
    throw UnimplementedError('ARAP warp engine not yet implemented');
  }

  @override
  BodyMultiPassResult? composeBodyMultiPass(BodyMultiPassInput input) => null;

  @override
  Future<TextureHandle> applyGPU({
    required TextureHandle input,
    required WarpField field,
    required GPURenderer renderer,
  }) async {
    throw UnimplementedError('ARAP warp engine not yet implemented');
  }
}

/// Stub mesh warp — Sprint futuro.
class MeshWarpEngine implements WarpEngine {
  const MeshWarpEngine();

  @override
  WarpAlgorithm get algorithm => WarpAlgorithm.meshWarp;

  @override
  WarpField compute(WarpRequest request) {
    throw UnimplementedError('Mesh warp engine not yet implemented');
  }

  @override
  BodyMultiPassResult? composeBodyMultiPass(BodyMultiPassInput input) => null;

  @override
  Future<TextureHandle> applyGPU({
    required TextureHandle input,
    required WarpField field,
    required GPURenderer renderer,
  }) async {
    throw UnimplementedError('Mesh warp engine not yet implemented');
  }
}
