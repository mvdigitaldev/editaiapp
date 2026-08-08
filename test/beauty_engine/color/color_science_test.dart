import 'dart:typed_data';

import 'package:editaiapp/features/editor/beauty_engine/color/color_science.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ColorScience sRGB <-> linear', () {
    test('extremos e meio-tom conhecidos', () {
      expect(ColorScience.srgbToLinear(0), 0);
      expect(ColorScience.srgbToLinear(1), closeTo(1.0, 1e-9));
      // sRGB 0.5 ≈ 0.2140 em luz linear (referência clássica).
      expect(ColorScience.srgbToLinear(0.5), closeTo(0.2140, 1e-3));
      expect(ColorScience.linearToSrgb(0.2140), closeTo(0.5, 1e-3));
    });

    test('round-trip 8-bit é exato em todos os 256 níveis', () {
      for (var i = 0; i < 256; i++) {
        final linear = ColorScience.srgbToLinearTable[i];
        expect(ColorScience.linearToSrgb8(linear), i, reason: 'nível $i');
      }
    });

    test('tabela concorda com a função escalar', () {
      for (var i = 0; i < 256; i += 17) {
        expect(
          ColorScience.srgbToLinearTable[i],
          closeTo(ColorScience.srgbToLinear(i / 255), 1e-6),
        );
      }
    });

    test('lumaFromRgba usa luz linear, não sRGB', () {
      // Cinza sRGB 50% tem luminância LINEAR ~0.214, não 0.5.
      final rgba = Uint8List.fromList([128, 128, 128, 255]);
      final luma = ColorScience.lumaFromRgba(rgba, 1, 1);
      expect(luma[0], closeTo(0.2158, 2e-3));
    });
  });

  group('ColorScience OKLab', () {
    test('round-trip linear RGB -> OKLab -> linear RGB', () {
      final lab = Float64List(3);
      final rgb = Float64List(3);
      const samples = [
        [0.0, 0.0, 0.0],
        [1.0, 1.0, 1.0],
        [0.5, 0.25, 0.12], // tom de pele médio
        [0.05, 0.02, 0.01], // pele escura em sombra
        [0.9, 0.7, 0.6], // pele clara em luz forte
      ];
      for (final sample in samples) {
        ColorScience.linearRgbToOklab(sample[0], sample[1], sample[2], lab);
        ColorScience.oklabToLinearRgb(lab[0], lab[1], lab[2], rgb);
        expect(rgb[0], closeTo(sample[0], 1e-6), reason: '$sample R');
        expect(rgb[1], closeTo(sample[1], 1e-6), reason: '$sample G');
        expect(rgb[2], closeTo(sample[2], 1e-6), reason: '$sample B');
      }
    });

    test('branco tem croma zero e L = 1', () {
      final lab = Float64List(3);
      ColorScience.linearRgbToOklab(1, 1, 1, lab);
      expect(lab[0], closeTo(1.0, 1e-4));
      expect(lab[1], closeTo(0.0, 1e-4));
      expect(lab[2], closeTo(0.0, 1e-4));
    });

    test('L cresce monotonicamente com a luminância', () {
      final lab = Float64List(3);
      var previous = -1.0;
      for (var v = 0.0; v <= 1.0; v += 0.1) {
        ColorScience.linearRgbToOklab(v, v, v, lab);
        expect(lab[0], greaterThan(previous));
        previous = lab[0];
      }
    });
  });
}
