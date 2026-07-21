import 'dart:typed_data';
import 'dart:ui';

import 'package:editaiapp/features/editor/beauty_engine/models/mesh_region.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/warp_field.dart';
import 'package:editaiapp/features/editor/beauty_engine/rendering/fps_benchmark.dart';
import 'package:editaiapp/features/editor/beauty_engine/rendering/gpu_renderer_impl.dart';
import 'package:editaiapp/features/editor/beauty_engine/rendering/render_target.dart';
import 'package:editaiapp/features/editor/beauty_engine/rendering/shader_program_cache.dart';
import 'package:editaiapp/features/editor/beauty_engine/rendering/texture_handle.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/warp_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GpuRendererImpl', () {
    late GpuRendererImpl renderer;

    setUp(() {
      renderer = GpuRendererImpl();
    });

    tearDown(() {
      renderer.dispose();
    });

    test('upload and readPixels round-trip', () async {
      final rgba = _solidRgba(width: 4, height: 4, r: 10, g: 20, b: 30);
      final handle = await renderer.upload(
        TextureUpload(bytes: rgba, width: 4, height: 4),
      );

      final read = await renderer.readPixels(handle);
      expect(read, rgba);
      renderer.release(handle);
    });

    test('exportJpeg produces valid JPEG header', () async {
      final rgba = _solidRgba(width: 8, height: 8, r: 200, g: 100, b: 50);
      final handle = await renderer.upload(
        TextureUpload(bytes: rgba, width: 8, height: 8),
      );

      final jpeg = await renderer.exportJpeg(handle, quality: 85);
      expect(jpeg.length, greaterThan(20));
      expect(jpeg[0], 0xFF);
      expect(jpeg[1], 0xD8);
      expect(jpeg[2], 0xFF);

      renderer.release(handle);
    });

    test('runPipeline color pass adjusts brightness', () async {
      final rgba = _solidRgba(width: 2, height: 2, r: 100, g: 100, b: 100);
      final input = await renderer.upload(
        TextureUpload(bytes: rgba, width: 2, height: 2),
      );

      final output = await renderer.runPipeline(
        input: input,
        stages: [
          const RenderPipelineStage(
            shaderName: RenderShaders.colorAdjust,
            uniforms: {'brightness': 0.2, 'contrast': 1.0},
          ),
        ],
      );

      final pixels = await renderer.readPixels(output);
      expect(pixels[0], greaterThan(100));

      renderer.release(input);
      renderer.release(output);
    });

    test('runPipeline composite blends overlay', () async {
      final base = _solidRgba(width: 2, height: 2, r: 0, g: 0, b: 0);
      final overlay = _solidRgba(width: 2, height: 2, r: 200, g: 0, b: 0);

      final baseHandle = await renderer.upload(
        TextureUpload(bytes: base, width: 2, height: 2),
      );
      final overlayHandle = await renderer.upload(
        TextureUpload(bytes: overlay, width: 2, height: 2),
      );

      final output = await renderer.runPipeline(
        input: baseHandle,
        stages: [
          RenderPipelineStage(
            shaderName: RenderShaders.composite,
            uniforms: {'overlay': overlayHandle, 'alpha': 0.5},
          ),
        ],
      );

      final pixels = await renderer.readPixels(output);
      expect(pixels[0], 100);

      renderer.release(baseHandle);
      renderer.release(overlayHandle);
      renderer.release(output);
    });

    test('identity warp pass returns copy', () async {
      final rgba = _solidRgba(width: 4, height: 4, r: 1, g: 2, b: 3);
      final input = await renderer.upload(
        TextureUpload(bytes: rgba, width: 4, height: 4),
      );

      final field = WarpField.identity(
        imageSize: const Size(4, 4),
        region: MeshRegion.jawLeft,
      );

      final output = await renderer.applyPass(
        input: input,
        shaderName: WarpEngine.warpRemapShader,
        uniforms: {'warpField': field},
      );

      expect(output.id, isNot(input.id));
      final pixels = await renderer.readPixels(output);
      expect(pixels, rgba);

      renderer.release(input);
      renderer.release(output);
    });
  });

  group('ShaderProgramCache', () {
    test('registers warp, color, lut and composite passes', () {
      final cache = ShaderProgramCache();
      expect(cache.contains(RenderShaders.warpRemap), isTrue);
      expect(cache.contains(RenderShaders.colorAdjust), isTrue);
      expect(cache.contains(RenderShaders.lutApply), isTrue);
      expect(cache.contains(RenderShaders.composite), isTrue);
      expect(cache.contains(RenderShaders.eyeOverlay), isTrue);
      expect(cache.contains(RenderShaders.cheekboneContour), isTrue);
      expect(cache.contains(RenderShaders.skinEngine), isTrue);
      expect(cache.contains(WarpEngine.warpRemapShader), isTrue);
    });
  });

  group('FpsBenchmark', () {
    test('720p identity warp meets preview FPS target', () async {
      const width = 1280;
      const height = 720;
      final renderer = GpuRendererImpl();
      final rgba = _solidRgba(width: width, height: height, r: 80, g: 120, b: 160);
      final input = await renderer.upload(
        TextureUpload(bytes: rgba, width: width, height: height),
      );

      final field = WarpField.identity(
        imageSize: Size(width.toDouble(), height.toDouble()),
        region: MeshRegion.jawLeft,
      );

      final result = await const FpsBenchmark().runWarpPass(
        renderer: renderer,
        input: input,
        warpUniforms: {'warpField': field},
        duration: const Duration(milliseconds: 300),
      );

      expect(result.frameCount, greaterThan(0));
      expect(result.width, width);
      expect(result.height, height);
      expect(result.fps, greaterThan(24));

      renderer.release(input);
      renderer.dispose();
    });
  });
}

Uint8List _solidRgba({
  required int width,
  required int height,
  required int r,
  required int g,
  required int b,
}) {
  final bytes = Uint8List(width * height * 4);
  for (var i = 0; i < width * height; i++) {
    final idx = i * 4;
    bytes[idx] = r;
    bytes[idx + 1] = g;
    bytes[idx + 2] = b;
    bytes[idx + 3] = 255;
  }
  return bytes;
}
