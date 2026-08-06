import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:editaiapp/features/editor/beauty_engine/body_reshape/brush/brush_warp_field_builder.dart';
import 'package:editaiapp/features/editor/beauty_engine/presets/lut_square_table.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/warp_cpu_remap.dart';
import 'package:flutter_test/flutter_test.dart';

import 'golden_test_utils.dart';

/// Baseline do pipeline ATUAL (Sprint 0 — cap. 11 do plano do SDK facial).
///
/// Esses goldens congelam o comportamento de hoje dos caminhos
/// determinísticos (warp remap CPU e LUT). As Fases 1–2 vão migrar passes
/// CPU→GPU; qualquer regressão silenciosa aparece aqui. Mudança intencional
/// de qualidade = regravar goldens com UPDATE_GOLDENS=1 e revisar o diff.
void main() {
  const width = 256;
  const height = 320;

  group('Baseline golden — pipeline atual', () {
    test('retrato sintético é determinístico', () {
      expectMatchesGolden(
        name: 'source_portrait',
        rgba: _syntheticPortrait(width, height),
        width: width,
        height: height,
        tolerance: GoldenTolerance.strict,
      );
    });

    test('warp: pincel pinch (remap CPU atual)', () {
      const builder = BrushWarpFieldBuilder(gridWidth: 64, gridHeight: 64);
      final field = builder.build(
        strokes: [
          const WarpStroke(
            points: [Offset(0.5, 0.42), Offset(0.5, 0.42)],
            radiusNormalized: 0.18,
            strength: 0.9,
            mode: WarpBrushMode.pinch,
          ),
        ],
        imageSize: const Size(width * 1.0, height * 1.0),
      );
      final out = const WarpCpuRemap().apply(
        rgba: _syntheticPortrait(width, height),
        width: width,
        height: height,
        field: field,
      );
      expectMatchesGolden(
        name: 'warp_brush_pinch',
        rgba: out,
        width: width,
        height: height,
      );
    });

    test('cor: LUT natural em intensidade 1 (motor atual)', () {
      final lut = LutSquareTable.buildNatural();
      final lutRgba = Uint8List(lut.width * lut.height * 4);
      var offset = 0;
      for (var y = 0; y < lut.height; y++) {
        for (var x = 0; x < lut.width; x++) {
          final pixel = lut.getPixel(x, y);
          lutRgba[offset++] = pixel.r.toInt();
          lutRgba[offset++] = pixel.g.toInt();
          lutRgba[offset++] = pixel.b.toInt();
          lutRgba[offset++] = pixel.a.toInt();
        }
      }

      final out = LutSquareTable.apply(
        sourceRgba: _syntheticPortrait(width, height),
        width: width,
        height: height,
        lutRgba: lutRgba,
        lutWidth: LutSquareTable.dimension,
        lutHeight: LutSquareTable.dimension,
        intensity: 1,
      );
      expectMatchesGolden(
        name: 'lut_natural_full',
        rgba: out,
        width: width,
        height: height,
      );
    });
  });
}

/// Retrato sintético determinístico: fundo em gradiente com listras, elipse
/// em tom de pele (rosto), faixa escura (cabelo) e detalhes de alta
/// frequência na "pele" para denunciar borrões/deslocamentos.
Uint8List _syntheticPortrait(int width, int height) {
  final rgba = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final nx = x / (width - 1);
      final ny = y / (height - 1);
      final i = (y * width + x) * 4;

      // Fundo: gradiente + listras verticais.
      var r = 40 + (nx * 60).round();
      var g = 60 + (ny * 80).round();
      var b = 110;
      if ((x ~/ 12).isEven) {
        r += 25;
        g += 25;
        b += 25;
      }

      // Rosto: elipse central em tom de pele com textura de "poros".
      final faceDist = math.pow((nx - 0.5) / 0.24, 2) +
          math.pow((ny - 0.42) / 0.30, 2);
      if (faceDist <= 1) {
        final texture = ((x * 7 + y * 13) % 17 == 0) ? -18 : 0;
        r = 224 + texture;
        g = 172 + texture;
        b = 148 + texture;
        // Olhos: dois pontos escuros.
        final leftEye = math.pow((nx - 0.42) / 0.03, 2) +
            math.pow((ny - 0.36) / 0.02, 2);
        final rightEye = math.pow((nx - 0.58) / 0.03, 2) +
            math.pow((ny - 0.36) / 0.02, 2);
        if (leftEye <= 1 || rightEye <= 1) {
          r = 50;
          g = 40;
          b = 35;
        }
        // Boca: faixa avermelhada.
        final mouth = math.pow((nx - 0.5) / 0.08, 2) +
            math.pow((ny - 0.56) / 0.015, 2);
        if (mouth <= 1) {
          r = 190;
          g = 90;
          b = 90;
        }
      }

      // Cabelo: calota acima do rosto.
      final hairDist = math.pow((nx - 0.5) / 0.28, 2) +
          math.pow((ny - 0.30) / 0.26, 2);
      if (hairDist <= 1 && ny < 0.26) {
        r = 55;
        g = 40;
        b = 30;
      }

      rgba[i] = r.clamp(0, 255);
      rgba[i + 1] = g.clamp(0, 255);
      rgba[i + 2] = b.clamp(0, 255);
      rgba[i + 3] = 255;
    }
  }
  return rgba;
}
