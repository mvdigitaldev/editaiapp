import 'dart:async';

import 'gpu_renderer_impl.dart';
import 'render_target.dart';
import 'texture_handle.dart';

/// Resultado de benchmark de FPS do pipeline GPU.
class FpsBenchmarkResult {
  final double fps;
  final int frameCount;
  final Duration elapsed;
  final int width;
  final int height;

  const FpsBenchmarkResult({
    required this.fps,
    required this.frameCount,
    required this.elapsed,
    required this.width,
    required this.height,
  });

  bool meetsTarget(double targetFps) => fps >= targetFps;
}

/// Harness para medir throughput do pipeline warp (preview).
class FpsBenchmark {
  const FpsBenchmark();

  Future<FpsBenchmarkResult> runWarpPass({
    required GpuRendererImpl renderer,
    required TextureHandle input,
    required Map<String, Object> warpUniforms,
    Duration duration = const Duration(milliseconds: 500),
  }) async {
    final entry = renderer.textureStore.get(input.id);
    if (entry == null) {
      return const FpsBenchmarkResult(
        fps: 0,
        frameCount: 0,
        elapsed: Duration.zero,
        width: 0,
        height: 0,
      );
    }

    final stopwatch = Stopwatch()..start();
    var frames = 0;
    TextureHandle? lastOutput;

    while (stopwatch.elapsed < duration) {
      final output = await renderer.applyPass(
        input: input,
        shaderName: RenderShaders.warpRemap,
        uniforms: warpUniforms,
      );
      if (lastOutput != null && lastOutput.id != output.id) {
        renderer.release(lastOutput);
      }
      lastOutput = output;
      frames++;
    }

    stopwatch.stop();
    if (lastOutput != null && lastOutput.id != input.id) {
      renderer.release(lastOutput);
    }

    final seconds = stopwatch.elapsed.inMicroseconds / 1e6;
    final fps = seconds > 0 ? frames / seconds : 0.0;

    return FpsBenchmarkResult(
      fps: fps,
      frameCount: frames,
      elapsed: stopwatch.elapsed,
      width: entry.width,
      height: entry.height,
    );
  }
}
