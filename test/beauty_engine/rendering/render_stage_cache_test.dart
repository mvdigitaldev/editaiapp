import 'dart:typed_data';

import 'package:editaiapp/features/editor/beauty_engine/filters/color/color_filter_pipeline.dart';
import 'package:editaiapp/features/editor/beauty_engine/rendering/gpu_renderer_impl.dart';
import 'package:editaiapp/features/editor/beauty_engine/rendering/render_stage_cache.dart';
import 'package:editaiapp/features/editor/beauty_engine/rendering/texture_handle.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RenderStageCache', () {
    test('ignora parâmetros de cor na chave', () {
      final rgba = Uint8List.fromList([10, 20, 30, 255]);
      final base = RenderStageCache.buildKey(
        sourceWidth: 1,
        sourceHeight: 1,
        sourceSampleHash: RenderStageCache.sampleRgbaHash(rgba),
        params: const {'skin_smooth': 0.5, 'exposure': 0},
        lutAssetPath: null,
      );
      final colorOnly = RenderStageCache.buildKey(
        sourceWidth: 1,
        sourceHeight: 1,
        sourceSampleHash: RenderStageCache.sampleRgbaHash(rgba),
        params: const {'skin_smooth': 0.5, 'exposure': 0.8},
        lutAssetPath: null,
      );
      expect(base, colorOnly);
    });

    test('store e reuse de textura', () async {
      final renderer = GpuRendererImpl();
      final cache = RenderStageCache();
      final input = await renderer.upload(
        TextureUpload(
          bytes: Uint8List.fromList([100, 120, 140, 255]),
          width: 1,
          height: 1,
        ),
      );
      const key = 42;
      cache.store(renderer, key, input);
      expect(cache.isValid(key), isTrue);
      expect(cache.preColorTexture, isNotNull);
      cache.clear(renderer);
      expect(cache.isValid(key), isFalse);
      renderer.dispose();
    });
  });
}
