import 'dart:typed_data';

import 'package:editaiapp/features/editor/filter_presets/filter_grade_engine.dart';
import 'package:editaiapp/features/editor/filter_presets/filter_preset.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  group('FilterGradeEngine', () {
    test('applyToJpeg retorna JPEG válido', () async {
      final engine = FilterGradeEngine();
      final image = img.Image(width: 8, height: 8);
      img.fill(image, color: img.ColorRgb8(120, 80, 200));
      final source = Uint8List.fromList(img.encodeJpg(image));

      final result = await engine.applyToJpeg(
        jpegBytes: source,
        tune: const FilterTuneParams(
          brightness: 0.05,
          contrast: 0.04,
          saturation: 0.03,
          vignette: 0.1,
        ),
      );

      expect(result, isNotEmpty);
      expect(result.length, greaterThan(50));
      expect(img.decodeJpg(result), isNotNull);
    });
  });
}
