import 'dart:typed_data';

import '../body_reshape/rendering/export_warp.dart';
import '../body_reshape/rendering/fragment_program_warp_backend.dart';
import '../body_reshape/rendering/method_channel_native_export_backend.dart';
import '../body_reshape/rendering/native_export_backend.dart';
import '../filters/face/skin/native_skin_backend.dart';
import 'export_encoder.dart';
import 'fragment_program_backend.dart';
import 'gpu_texture_store.dart';
import 'render_pass.dart';
import 'render_target.dart';
import 'shader_program_cache.dart';
import 'texture_handle.dart';
import 'texture_pool.dart';

/// Pipeline multi-pass com texture pool e export encoder.
///
/// Preview de warp: [FragmentProgramWarpBackend] (Impeller). Export: [ExportWarp]
/// (native Metal/GLES → FragmentProgram). Fallback CPU apenas quando explícito.
class GpuRendererImpl implements GPURenderer {
  GpuRendererImpl._({
    required TexturePool pool,
    required bool forceCpuWarp,
    required FragmentProgramWarpBackend warpBackend,
    required NativeExportBackend nativeExportBackend,
    required ExportWarp resolvedExportWarp,
    required ExportEncoder resolvedExportEncoder,
    NativeSkinBackend? nativeSkinBackend,
    ShaderProgramCache? shaderCache,
  })  : _pool = pool,
        _forceCpuWarp = forceCpuWarp,
        _warpBackend = warpBackend,
        _nativeExportBackend = nativeExportBackend,
        _exportWarp = resolvedExportWarp,
        _exportEncoder = resolvedExportEncoder,
        _shaderCache = shaderCache ??
            ShaderProgramCache(
              warpBackend: warpBackend,
              nativeSkinBackend: nativeSkinBackend,
              preferGpuWarp: !forceCpuWarp,
            );

  factory GpuRendererImpl({
    TexturePool? pool,
    ShaderProgramCache? shaderCache,
    ExportEncoder? exportEncoder,
    FragmentProgramWarpBackend? warpBackend,
    NativeExportBackend? nativeExportBackend,
    NativeSkinBackend? nativeSkinBackend,
    ExportWarp? exportWarp,
    bool forceCpuWarp = false,
  }) {
    final resolvedPool = pool ?? TexturePool();
    final resolvedWarp = warpBackend ??
        FragmentProgramWarpBackend(forceCpuFallback: forceCpuWarp);
    final resolvedNative =
        nativeExportBackend ?? MethodChannelNativeExportBackend();
    final resolvedSkin =
        nativeSkinBackend ?? MethodChannelNativeSkinBackend();
    final resolvedExport = exportWarp ??
        ExportWarp(
          fragmentBackend: resolvedWarp,
          nativeBackend: resolvedNative,
        );
    return GpuRendererImpl._(
      pool: resolvedPool,
      forceCpuWarp: forceCpuWarp,
      warpBackend: resolvedWarp,
      nativeExportBackend: resolvedNative,
      resolvedExportWarp: resolvedExport,
      resolvedExportEncoder:
          exportEncoder ?? ExportEncoder(exportWarp: resolvedExport),
      nativeSkinBackend: resolvedSkin,
      shaderCache: shaderCache,
    );
  }

  final TexturePool _pool;
  final ShaderProgramCache _shaderCache;
  final ExportEncoder _exportEncoder;
  final FragmentProgramWarpBackend _warpBackend;
  final NativeExportBackend _nativeExportBackend;
  final ExportWarp _exportWarp;
  final bool _forceCpuWarp;
  bool _initialized = false;

  ShaderProgramCache get shaderCache => _shaderCache;

  GpuTextureStore get textureStore => _pool.store;

  FragmentProgramBackend get fragmentBackend => _warpBackend;

  ExportWarp get exportWarp => _exportWarp;

  NativeExportBackend get nativeExportBackend => _nativeExportBackend;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    await _warpBackend.initialize();
    _initialized = true;
  }

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
    await initialize();
    final pass = _shaderCache.getPass(shaderName);
    final merged = Map<String, Object>.from(uniforms);
    if (_forceCpuWarp) {
      merged['forceCpu'] = true;
    }
    final context = RenderPassContext(
      input: input,
      pool: _pool,
      uniforms: merged,
    );
    return pass.execute(context);
  }

  @override
  Future<TextureHandle> runPipeline({
    required TextureHandle input,
    required List<RenderPipelineStage> stages,
  }) async {
    await initialize();
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
    return _exportEncoder.encodeJpegAsync(entry, quality: quality);
  }

  @override
  void release(TextureHandle texture) {
    _pool.release(texture);
  }

  /// Cópia independente — usada pelo cache de estágio pós-pele.
  TextureHandle copyTexture(TextureHandle source) => _pool.acquireCopy(source);

  @override
  void dispose() {
    _pool.releaseAll();
    _exportWarp.dispose();
    if (!identical(_warpBackend, FragmentProgramWarpBackend.shared)) {
      _warpBackend.dispose();
    }
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
