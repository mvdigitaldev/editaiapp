import 'dart:typed_data';

import 'export_encoder.dart';
import 'gpu_texture_store.dart';
import 'render_pass.dart';
import 'render_target.dart';
import 'shader_program_cache.dart';
import 'texture_handle.dart';
import 'texture_pool.dart';

/// Pipeline GPU multi-pass com texture pool e export encoder.
///
/// Backend CPU hoje; interface pronta para FragmentProgram/Impeller (Sprint 08+).
class GpuRendererImpl implements GPURenderer {
  GpuRendererImpl({
    TexturePool? pool,
    ShaderProgramCache? shaderCache,
    ExportEncoder? exportEncoder,
  })  : _pool = pool ?? TexturePool(),
        _shaderCache = shaderCache ?? ShaderProgramCache(),
        _exportEncoder = exportEncoder ?? const ExportEncoder();

  final TexturePool _pool;
  final ShaderProgramCache _shaderCache;
  final ExportEncoder _exportEncoder;

  ShaderProgramCache get shaderCache => _shaderCache;

  GpuTextureStore get textureStore => _pool.store;

  @override
  Future<TextureHandle> upload(TextureUpload upload) async {
    return _pool.acquireFromUpload(upload);
  }

  @override
  Future<TextureHandle> applyPass({
    required TextureHandle input,
    required String shaderName,
    Map<String, Object> uniforms = const {},
  }) async {
    final pass = _shaderCache.getPass(shaderName);
    final context = RenderPassContext(
      input: input,
      pool: _pool,
      uniforms: uniforms,
    );
    return pass.execute(context);
  }

  @override
  Future<TextureHandle> runPipeline({
    required TextureHandle input,
    required List<RenderPipelineStage> stages,
  }) async {
    var current = input;
    for (final stage in stages) {
      final next = await applyPass(
        input: current,
        shaderName: stage.shaderName,
        uniforms: stage.uniforms,
      );
      if (current.id != input.id && current.id != next.id) {
        release(current);
      }
      current = next;
    }
    return current;
  }

  @override
  Future<Uint8List> readPixels(TextureHandle texture) async {
    final entry = _pool.store.get(texture.id);
    if (entry == null) {
      return Uint8List(0);
    }
    return Uint8List.fromList(entry.rgba);
  }

  @override
  Future<Uint8List> exportJpeg(
    TextureHandle texture, {
    int quality = 90,
  }) async {
    final entry = _pool.store.get(texture.id);
    if (entry == null) {
      return Uint8List(0);
    }
    return _exportEncoder.encodeJpeg(entry, quality: quality);
  }

  @override
  void release(TextureHandle texture) {
    _pool.release(texture);
  }

  @override
  void dispose() {
    _pool.releaseAll();
  }
}

/// Interface publica do renderer (Sprint 07).
abstract class GPURenderer {
  Future<TextureHandle> upload(TextureUpload upload);

  Future<TextureHandle> applyPass({
    required TextureHandle input,
    required String shaderName,
    Map<String, Object> uniforms,
  });

  Future<TextureHandle> runPipeline({
    required TextureHandle input,
    required List<RenderPipelineStage> stages,
  });

  Future<Uint8List> readPixels(TextureHandle texture);

  Future<Uint8List> exportJpeg(TextureHandle texture, {int quality = 90});

  void release(TextureHandle texture);

  void dispose();
}
