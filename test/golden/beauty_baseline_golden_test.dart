import 'dart:typed_data';
import 'dart:ui';

import 'package:editaiapp/features/editor/beauty_engine/body_reshape/brush/brush_warp_field_builder.dart';
import 'package:editaiapp/features/editor/beauty_engine/presets/lut_square_table.dart';
import 'package:editaiapp/features/editor/beauty_engine/warp/warp_cpu_remap.dart';
import 'package:flutter_test/flutter_test.dart';

import 'golden_test_utils.dart';
import 'synthetic_portrait.dart';

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
        rgba: syntheticPortrait(width, height),
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
        rgba: syntheticPortrait(width, height),
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
        sourceRgba: syntheticPortrait(width, height),
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
