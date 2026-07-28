import 'dart:typed_data';

import '../body_reshape/rendering/export_warp.dart';
import '../body_reshape/rendering/fragment_program_warp_backend.dart';
import '../body_reshape/rendering/native_export_backend.dart';
import 'fragment_program_backend.dart';
import 'gpu_renderer_impl.dart';
import 'gpu_texture_store.dart';
import 'render_target.dart';
import 'shader_program_cache.dart';
import 'texture_handle.dart';

/// Alias retrocompatível — delega para [GpuRendererImpl].
class GPURendererStub implements GPURenderer {
  GPURendererStub({
    bool forceCpuWarp = false,
  }) : _impl = GpuRendererImpl(forceCpuWarp: forceCpuWarp);

  final GpuRendererImpl _impl;

  ShaderProgramCache get shaderCache => _impl.shaderCache;

  GpuTextureStore get textureStore => _impl.textureStore;

  FragmentProgramBackend get fragmentBackend => _impl.fragmentBackend;

  ExportWarp get exportWarp => _impl.exportWarp;

  NativeExportBackend get nativeExportBackend => _impl.nativeExportBackend;

  Future<void> initialize() => _impl.initialize();

  @override
  Future<TextureHandle> upload(TextureUpload upload) => _impl.upload(upload);

  @override
  Future<TextureHandle> applyPass({
    required TextureHandle input,
    required String shaderName,
    Map<String, Object> uniforms = const {},
  }) =>
      _impl.applyPass(
        input: input,
        shaderName: shaderName,
        uniforms: uniforms,
      );

  @override
  Future<TextureHandle> runPipeline({
    required TextureHandle input,
    required List<RenderPipelineStage> stages,
  }) =>
      _impl.runPipeline(input: input, stages: stages);

  @override
  Future<Uint8List> readPixels(TextureHandle texture) =>
      _impl.readPixels(texture);

  @override
  Future<Uint8List> exportJpeg(TextureHandle texture, {int quality = 90}) =>
      _impl.exportJpeg(texture, quality: quality);

  @override
  void release(TextureHandle texture) => _impl.release(texture);

  @override
  void dispose() => _impl.dispose();
}
