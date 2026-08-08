import 'dart:typed_data';
import 'dart:ui';

import 'package:editaiapp/features/editor/beauty_engine/filters/face/skin/skin_weight_map.dart';
import 'package:editaiapp/features/editor/beauty_engine/filters/face/skin_filter_pipeline.dart';
import 'package:editaiapp/features/editor/beauty_engine/filters/face/skin_mask_utils.dart';
import 'package:editaiapp/features/editor/beauty_engine/rendering/gpu_renderer_impl.dart';
import 'package:editaiapp/features/editor/beauty_engine/rendering/texture_handle.dart';
import 'package:flutter_test/flutter_test.dart';

import '../beauty_engine/filters/skin/skin_face_fixture.dart';
import 'golden_test_utils.dart';
import 'synthetic_portrait.dart';

/// Goldens do Grupo A (pele) rodando o pipeline REAL: máscara a partir dos
/// landmarks + `PassSkinEngine` + `SkinRetouchEngine`.
///
/// Além do golden, cada teste afirma os invariantes das fichas de
/// `docs/beauty/13-visual-quality-targets.md` — o golden pega regressão
/// silenciosa, os invariantes pegam regressão de qualidade.
void main() {
  const width = 256;
  const height = 320;
  const imageSize = Size(width * 1.0, height * 1.0);

  Future<Uint8List> renderSkin(Map<String, double> parameters) async {
    final source = syntheticPortrait(width, height);
    final renderer = GpuRendererImpl();
    final input = await renderer.upload(
      TextureUpload(bytes: source, width: width, height: height),
    );
    final stages = const SkinFilterPipeline().buildPostStages(
      parameters: parameters,
      face: syntheticFace(),
      imageSize: imageSize,
    );
    expect(stages, isNotEmpty, reason: 'pipeline de pele não gerou stage');

    final output = await renderer.runPipeline(input: input, stages: stages);
    final rgba = await renderer.readPixels(output);
    renderer.dispose();
    return rgba;
  }

  int index(double nx, double ny) =>
      (((ny * height).round().clamp(0, height - 1)) * width +
              ((nx * width).round().clamp(0, width - 1))) *
          4;

  void expectUntouched(
    Uint8List output,
    Uint8List source,
    Offset point,
    String label,
  ) {
    final i = index(point.dx, point.dy);
    expect(output[i], source[i], reason: '$label R');
    expect(output[i + 1], source[i + 1], reason: '$label G');
    expect(output[i + 2], source[i + 2], reason: '$label B');
  }

  group('Golden Grupo A — pele', () {
    test('suavizar pele no máximo', () async {
      final source = syntheticPortrait(width, height);
      final output = await renderSkin(const {'skin_smooth': 1.0});

      expectMatchesGolden(
        name: 'skin_smooth_full',
        rgba: output,
        width: width,
        height: height,
      );

      // A1: fundo, cabelo, olhos e boca não podem mudar.
      expectUntouched(output, source, const Offset(0.03, 0.05), 'fundo');
      expectUntouched(output, source, const Offset(0.5, 0.12), 'cabelo');
      expectUntouched(output, source, leftEyeCenter, 'olho esquerdo');
      expectUntouched(output, source, rightEyeCenter, 'olho direito');
      expectUntouched(output, source, mouthCenter, 'boca');

      // A pele mudou de fato (senão os invariantes acima seriam vácuo).
      // Pele lisa não muda — o que deve mudar são os "poros" (pontos de alta
      // frequência), atenuados em direção ao tom base.
      final weights = SkinWeightMap.build(
        width: width,
        height: height,
        geometric: SkinMaskUtils.build(syntheticFace(), imageSize),
      );

      var changed = 0;
      var poresAttenuated = 0;
      var pores = 0;
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          final i = (y * width + x) * 4;
          if (output[i] != source[i]) changed++;
          if (source[i] != 206) continue; // 224 - 18 = ponto de poro
          if (weights.weightAt(x, y) < 0.9) continue;
          pores++;
          if (output[i] > source[i]) poresAttenuated++;
        }
      }

      expect(changed, greaterThan(500), reason: 'pele praticamente intocada');
      expect(pores, greaterThan(100), reason: 'fixture sem poros para medir');
      expect(poresAttenuated / pores, greaterThan(0.9));
    });

    test('combinação de acne, olheiras e brilho', () async {
      final source = syntheticPortrait(width, height);
      final output = await renderSkin(const {
        'remove_acne': 0.8,
        'remove_dark_circles': 0.7,
        'skin_shine': 0.6,
      });

      expectMatchesGolden(
        name: 'skin_group_a_combo',
        rgba: output,
        width: width,
        height: height,
      );

      expectUntouched(output, source, const Offset(0.03, 0.05), 'fundo');
      expectUntouched(output, source, const Offset(0.5, 0.12), 'cabelo');
      expectUntouched(output, source, leftEyeCenter, 'olho esquerdo');
      expectUntouched(output, source, mouthCenter, 'boca');
    });

    test('todos os sliders em zero devolve a imagem original', () async {
      final source = syntheticPortrait(width, height);
      final renderer = GpuRendererImpl();
      final input = await renderer.upload(
        TextureUpload(bytes: source, width: width, height: height),
      );
      final stages = const SkinFilterPipeline().buildPostStages(
        parameters: const {'skin_smooth': 0},
        face: syntheticFace(),
        imageSize: imageSize,
      );
      expect(stages, isEmpty);

      final rgba = await renderer.readPixels(input);
      renderer.dispose();
      expect(rgba, source);
    });
  });
}
