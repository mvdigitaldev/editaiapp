import 'dart:typed_data';

import '../rendering/gpu_renderer.dart';
import '../rendering/gpu_renderer_impl.dart';
import '../rendering/render_target.dart';
import '../rendering/shader_program_cache.dart';

/// Compila/inicializa passes no open do editor para evitar jank (Sprint 25).
class ShaderPrewarmService {
  const ShaderPrewarmService();

  Future<void> prewarm(GPURenderer renderer) async {
    if (renderer is! GpuRendererImpl) {
      return;
    }

    final rgba = Uint8List(16);
    for (var i = 0; i < 16; i += 4) {
      rgba[i] = 128;
      rgba[i + 1] = 128;
      rgba[i + 2] = 128;
      rgba[i + 3] = 255;
    }

    final input = await renderer.upload(
      TextureUpload(bytes: rgba, width: 2, height: 2),
    );

    try {
      for (final shader in renderer.shaderCache.registeredShaders) {
        TextureHandle? output;
        try {
          output = await _warmShader(renderer, shader, input);
        } finally {
          if (output != null &&
              output.id != input.id &&
              renderer.textureStore.get(output.id) != null) {
            renderer.release(output);
          }
        }
      }
    } finally {
      renderer.release(input);
    }
  }

  Future<TextureHandle> _warmShader(
    GpuRendererImpl renderer,
    String shaderName,
    TextureHandle input,
  ) {
    switch (shaderName) {
      case RenderShaders.warpRemap:
        return renderer.applyPass(
          input: input,
          shaderName: shaderName,
          uniforms: const {},
        );
      case RenderShaders.lutApply:
        return renderer.applyPass(
          input: input,
          shaderName: shaderName,
          uniforms: const {'intensity': 0.0},
        );
      case RenderShaders.colorAdjust:
        return renderer.applyPass(
          input: input,
          shaderName: shaderName,
          uniforms: const {'brightness': 0.0, 'contrast': 1.0},
        );
      default:
        return renderer.applyPass(
          input: input,
          shaderName: shaderName,
          uniforms: const {},
        );
    }
  }
}
