import 'dart:typed_data';

import 'package:editaiapp/features/editor/beauty_engine/filters/color/color_grade_engine.dart';
import 'package:editaiapp/features/editor/beauty_engine/models/tune_params.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const engine = ColorGradeEngine();

  Uint8List solid(int r, int g, int b, {int width = 4, int height = 4}) {
    final rgba = Uint8List(width * height * 4);
    for (var i = 0; i < rgba.length; i += 4) {
      rgba[i] = r;
      rgba[i + 1] = g;
      rgba[i + 2] = b;
      rgba[i + 3] = 255;
    }
    return rgba;
  }

  group('ColorGradeEngine', () {
    test('identidade quando TuneParams vazio', () {
      final source = solid(120, 80, 60);
      final out = engine.applyToRgba(
        sourceRgba: source,
        width: 4,
        height: 4,
        tune: const TuneParams(),
      );
      expect(out, source);
    });

    test('exposição clareia pixels médios', () {
      final source = solid(128, 128, 128);
      final out = engine.applyToRgba(
        sourceRgba: source,
        width: 4,
        height: 4,
        tune: const TuneParams(exposure: 0.5),
      );
      expect(out[0], greaterThan(source[0]));
    });

    test('vinheta escurece cantos', () {
      const w = 32;
      const h = 32;
      final source = solid(200, 200, 200, width: w, height: h);
      final out = engine.applyToRgba(
        sourceRgba: source,
        width: w,
        height: h,
        tune: const TuneParams(vignette: 0.8),
      );
      final center = out[((h ~/ 2) * w + (w ~/ 2)) * 4];
      final corner = out[0];
      expect(corner, lessThan(center));
    });

    test('nitidez altera pixels sem proteção', () {
      const w = 8;
      const h = 8;
      final source = solid(100, 100, 100, width: w, height: h);
      source[4] = 180; // contraste local
      final out = engine.applyToRgba(
        sourceRgba: source,
        width: w,
        height: h,
        tune: const TuneParams(sharpness: 0.5),
      );
      expect(out[4], isNot(source[4]));
    });
  });
}
