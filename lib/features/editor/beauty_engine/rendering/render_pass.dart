import 'gpu_texture_store.dart';
import 'texture_handle.dart';
import 'texture_pool.dart';

/// Contexto compartilhado entre render passes.
class RenderPassContext {
  RenderPassContext({
    required this.input,
    required this.pool,
    required this.uniforms,
  });

  final TextureHandle input;
  final TexturePool pool;
  final Map<String, Object> uniforms;

  GpuTextureStore get store => pool.store;
}

/// Pass individual do pipeline GPU.
abstract class RenderPass {
  String get shaderName;

  Future<TextureHandle> execute(RenderPassContext context);
}
