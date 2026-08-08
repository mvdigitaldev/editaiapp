import 'dart:typed_data';

import 'package:editaiapp/features/editor/beauty_engine/filters/color/color_filter_pipeline.dart';
import 'package:editaiapp/features/editor/beauty_engine/rendering/gpu_renderer_impl.dart';
import 'package:editaiapp/features/editor/beauty_engine/rendering/texture_handle.dart';
import 'package:flutter_test/flutter_test.dart';

import 'golden_test_utils.dart';
import 'synthetic_portrait.dart';

/// Goldens do Grupo D (cor global) — Sprint 2.
void main() {
  const width = 256;
  const height = 320;

  Future<Uint8List> renderColor(Map<String, double> parameters) async {
    final source = syntheticPortrait(width, height);
    final renderer = GpuRendererImpl();
    final input = await renderer.upload(
      TextureUpload(bytes: source, width: width, height: height),
    );
    final stages = const ColorFilterPipeline().buildColorStages(
      parameters: parameters,
    );
    expect(stages, isNotEmpty);

    final output = await renderer.runPipeline(input: input, stages: stages);
    final rgba = await renderer.readPixels(output);
    renderer.dispose();
    return rgba;
  }

  group('Golden Grupo D — cor', () {
    test('exposição + saturação combo', () async {
      final source = syntheticPortrait(width, height);
      final output = await renderColor(const {
        'exposure': 0.15,
        'saturation': 0.25,
        'contrast': 0.1,
      });

      expectMatchesGolden(
        name: 'color_exposure_sat_combo',
        rgba: output,
        width: width,
        height: height,
      );

      // D1: ajuste global — cantos (fundo) mudam junto com o centro.
      final centerIdx = ((height ~/ 2) * width + (width ~/ 2)) * 4;
      final cornerIdx = 0;
      expect(output[centerIdx], isNot(source[centerIdx]));
      expect(output[cornerIdx], isNot(source[cornerIdx]));

      // Sem artefato de canal isolado: G e B também movem.
      expect(output[centerIdx + 1], isNot(source[centerIdx + 1]));
      expect(output[centerIdx + 2], isNot(source[centerIdx + 2]));
    });

    test('vinheta escurece bordas uniformemente', () async {
      final source = syntheticPortrait(width, height);
      final output = await renderColor(const {'vignette': 0.7});

      final centerIdx = ((height ~/ 2) * width + (width ~/ 2)) * 4;
      final cornerIdx = 0;
      expect(output[cornerIdx], lessThan(output[centerIdx]));
      expect(output[cornerIdx], lessThanOrEqualTo(source[cornerIdx]));
    });
  });
}
